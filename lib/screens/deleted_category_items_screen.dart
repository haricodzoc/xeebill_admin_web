import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/item_model.dart';

class DeletedCategoryItemsScreen extends StatefulWidget {
  final String userId;
  final String categoryCode;
  final String categoryName;

  const DeletedCategoryItemsScreen({
    super.key,
    required this.userId,
    required this.categoryCode,
    required this.categoryName,
  });

  @override
  State<DeletedCategoryItemsScreen> createState() =>
      _DeletedCategoryItemsScreenState();
}

class _DeletedCategoryItemsScreenState
    extends State<DeletedCategoryItemsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  String? _errorMessage;
  List<ItemModel> _items = [];

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // First, find the user document
      String? userDocumentId;

      final userQuery = await _firestore
          .collection('users')
          .where('userId', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        userDocumentId = userQuery.docs.first.id;
      } else {
        final userDoc = await _firestore
            .collection('users')
            .doc(widget.userId)
            .get();

        if (userDoc.exists) {
          userDocumentId = widget.userId;
        }
      }

      if (userDocumentId == null) {
        setState(() {
          _errorMessage = 'User document not found';
          _isLoading = false;
        });
        return;
      }

      // Fetch items with the deleted category code
      final itemsSnapshot = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('items')
          .where('category_code', isEqualTo: widget.categoryCode)
          .get();

      final List<ItemModel> allItems = [];

      for (var itemDoc in itemsSnapshot.docs) {
        try {
          final item = ItemModel.fromFirestore(itemDoc);
          allItems.add(item);
        } catch (e) {
          debugPrint('Error parsing item ${itemDoc.id}: $e');
        }
      }

      // Sort items by name
      allItems.sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _items = allItems;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching items: $e');
      setState(() {
        _errorMessage = 'Error fetching items: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Items Using Deleted Category'),
            Text(
              widget.categoryName,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchItems,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No items found',
                    style: TextStyle(color: Colors.grey[600], fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Category: ${widget.categoryCode}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchItems,
              child: Column(
                children: [
                  // Summary Card
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning,
                          color: Colors.orange[700],
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_items.length} item${_items.length == 1 ? '' : 's'} using deleted category',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[900],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Category: ${widget.categoryCode}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Items List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        return _buildItemCard(_items[index]);
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildItemCard(ItemModel item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: Icon(Icons.inventory_2, color: Colors.blue[700]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Code: ${item.code}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(item.active ? 'Active' : 'Inactive'),
                  backgroundColor: item.active
                      ? Colors.green[50]
                      : Colors.red[50],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: item.active ? Colors.green[700] : Colors.red[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildInfoChip(
                  Icons.currency_rupee,
                  'Price: ₹${item.price.toStringAsFixed(2)}',
                ),
                _buildInfoChip(
                  Icons.sell,
                  'Sell: ₹${item.sellPrice.toStringAsFixed(2)}',
                ),
                if (item.taxPerc != null)
                  _buildInfoChip(
                    Icons.percent,
                    'Tax: ${item.taxPerc!.toStringAsFixed(2)}%',
                  ),
                _buildInfoChip(
                  Icons.inventory,
                  'Qty: ${item.quantity.toStringAsFixed(2)}',
                ),
                _buildInfoChip(
                  Icons.category,
                  'Category: ${item.categoryCode}',
                  Colors.orange,
                ),
              ],
            ),
            if (item.description != null && item.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Description: ${item.description}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
            if (item.hsnCode != null && item.hsnCode!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'HSN: ${item.hsnCode}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, [Color? color]) {
    final chipColor = color ?? Colors.blue;
    return Chip(
      avatar: Icon(icon, size: 16, color: chipColor),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[700],
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: chipColor.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
