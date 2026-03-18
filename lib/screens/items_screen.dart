import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../models/item_model.dart';
import 'edit_item_dialog.dart';

class ItemsScreen extends StatefulWidget {
  final String userId;

  const ItemsScreen({super.key, required this.userId});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  String? _errorMessage;
  List<ItemModel> _items = [];
  String?
  _checkingDeleteItemCode; // Track which item is being checked for deletion

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
      debugPrint('Fetching items for user: ${widget.userId}');

      // First, find the user document
      String? userDocumentId;

      // Try to find user by userId field
      final userQuery = await _firestore
          .collection('users')
          .where('userId', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        userDocumentId = userQuery.docs.first.id;
        debugPrint('Found user document: $userDocumentId');
      } else {
        // Try by document ID
        final userDoc = await _firestore
            .collection('users')
            .doc(widget.userId)
            .get();

        if (userDoc.exists) {
          userDocumentId = widget.userId;
          debugPrint('Found user by document ID: $userDocumentId');
        }
      }

      if (userDocumentId == null) {
        setState(() {
          _errorMessage = 'User document not found';
          _isLoading = false;
        });
        return;
      }

      // Fetch items directly from users/{userId}/items subcollection
      debugPrint('Fetching items from users/$userDocumentId/items');

      final itemsSnapshot = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('items')
          .get();

      debugPrint('Found ${itemsSnapshot.docs.length} items');

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
      allItems.sort((a, b) {
        return a.name.compareTo(b.name);
      });

      setState(() {
        _items = allItems;
        _isLoading = false;
      });

      debugPrint('Successfully loaded ${allItems.length} items');
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
            const Text('Items'),
            if (!_isLoading && _items.isNotEmpty)
              Text(
                '${_items.length} item${_items.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _fetchItems,
          ),
        ],
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
                    'User ID: ${widget.userId}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchItems,
              child: ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  return _buildItemCard(_items[index]);
                },
              ),
            ),
    );
  }

  Widget _buildItemCard(ItemModel item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showItemDetailsModal(item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.orange[100],
                    child: Icon(Icons.inventory_2, color: Colors.orange[700]),
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
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_checkingDeleteItemCode == item.code)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _handleDeleteItem(item),
                      tooltip: 'Delete item',
                    ),
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text('Category: ${item.categoryCode}'),
                    backgroundColor: Colors.blue[50],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                  Chip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.printed ? Icons.check_circle : Icons.cancel,
                          size: 14,
                          color: item.printed ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(item.printed ? 'Printed' : 'Not Printed'),
                      ],
                    ),
                    backgroundColor: item.printed
                        ? Colors.green[50]
                        : Colors.red[50],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showItemDetailsModal(ItemModel item) {
    // Parse attributes JSON string
    Map<String, dynamic>? parsedAttributes;
    if (item.attributes.isNotEmpty) {
      try {
        parsedAttributes = jsonDecode(item.attributes) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing attributes: $e');
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.orange[100],
                      radius: 24,
                      child: Icon(Icons.inventory_2, color: Colors.orange[700]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Code: ${item.code}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit',
                      onPressed: () {
                        Navigator.pop(context);
                        _showEditItemDialog(item);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildDetailRow('Name', item.name),
                    _buildDetailRow('Code', item.code),
                    _buildDetailRow('Category Code', item.categoryCode),
                    _buildDetailRow(
                      'Price',
                      '₹${item.price.toStringAsFixed(2)}',
                    ),
                    _buildDetailRow(
                      'Sell Price',
                      '₹${item.sellPrice.toStringAsFixed(2)}',
                    ),
                    _buildDetailRow('Quantity', item.quantity.toString()),
                    _buildDetailRow(
                      'Available Quantity',
                      item.availableQty.toString(),
                    ),
                    _buildDetailRow('Unit', item.unit),
                    if (item.taxPerc != null)
                      _buildDetailRow(
                        'Tax %',
                        '${item.taxPerc!.toStringAsFixed(2)}%',
                      ),
                    if (item.hsnCode != null && item.hsnCode!.isNotEmpty)
                      _buildDetailRow('HSN Code', item.hsnCode!),
                    if (item.description != null &&
                        item.description!.isNotEmpty)
                      _buildDetailRow('Description', item.description!),
                    if (item.scannedBarcode != null &&
                        item.scannedBarcode!.isNotEmpty)
                      _buildDetailRow('Scanned Barcode', item.scannedBarcode!),
                    if (item.additionalInfo.isNotEmpty)
                      _buildDetailRow('Additional Info', item.additionalInfo),
                    _buildDetailRow(
                      'Status',
                      item.active ? 'Active' : 'Inactive',
                    ),
                    _buildDetailRow('Printed', item.printed ? 'Yes' : 'No'),
                    _buildDetailRow('Mapped', item.mapped ? 'Yes' : 'No'),
                    _buildDetailRow(
                      'Listed Online',
                      item.listedOnline ? 'Yes' : 'No',
                    ),
                    if (item.slNo != null)
                      _buildDetailRow('SL No', item.slNo.toString()),
                    _buildDetailRow(
                      'Created At',
                      _formatDateTime(item.createdAt),
                    ),
                    _buildDetailRow(
                      'Updated At',
                      _formatDateTime(item.updatedAt),
                    ),
                    if (parsedAttributes != null &&
                        parsedAttributes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Attributes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: parsedAttributes.entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 100,
                                    child: Text(
                                      '${entry.key}:',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      entry.value.toString(),
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ] else if (item.attributes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Attributes (Raw)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          item.attributes,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _showEditItemDialog(ItemModel item) {
    showDialog(
      context: context,
      builder: (context) => EditItemDialog(
        item: item,
        userId: widget.userId,
        onUpdated: () {
          _fetchItems();
        },
      ),
    );
  }

  Future<String?> _getUserDocumentId() async {
    try {
      // Try to find user by userId field
      final userQuery = await _firestore
          .collection('users')
          .where('userId', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        return userQuery.docs.first.id;
      }

      // Try by document ID
      final userDoc = await _firestore
          .collection('users')
          .doc(widget.userId)
          .get();

      if (userDoc.exists) {
        return widget.userId;
      }

      return null;
    } catch (e) {
      debugPrint('Error getting user document ID: $e');
      return null;
    }
  }

  Future<int> _checkItemInBills(String itemCode) async {
    try {
      final userDocumentId = await _getUserDocumentId();

      if (userDocumentId == null) {
        return 0;
      }

      // Fetch all bills for the user
      final billsSnapshot = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('bills')
          .get();

      int billCount = 0;

      // Check each bill for the item code
      for (var billDoc in billsSnapshot.docs) {
        final billData = billDoc.data();

        // Check if bill has items array
        if (billData.containsKey('items') && billData['items'] != null) {
          final items = billData['items'];
          if (items is List) {
            // Items stored as array
            for (var item in items) {
              if (item is Map<String, dynamic>) {
                final itemCodeInBill = item['code']?.toString() ?? '';
                if (itemCodeInBill == itemCode) {
                  billCount++;
                  break; // Found in this bill, move to next bill
                }
              }
            }
          }
        }

        // Also check bill_items subcollection if it exists
        try {
          final billItemsSnapshot = await _firestore
              .collection('users')
              .doc(userDocumentId)
              .collection('bills')
              .doc(billDoc.id)
              .collection('bill_items')
              .where('code', isEqualTo: itemCode)
              .limit(1)
              .get();

          if (billItemsSnapshot.docs.isNotEmpty) {
            billCount++;
          }
        } catch (e) {
          // Subcollection might not exist, that's okay
          debugPrint('Error checking bill_items subcollection: $e');
        }
      }

      return billCount;
    } catch (e) {
      debugPrint('Error checking item in bills: $e');
      return 0;
    }
  }

  Future<void> _handleDeleteItem(ItemModel item) async {
    // Set loading state
    setState(() {
      _checkingDeleteItemCode = item.code;
    });

    try {
      // Check if item is used in any bills
      final billCount = await _checkItemInBills(item.code);

      // Clear loading state
      setState(() {
        _checkingDeleteItemCode = null;
      });

      if (billCount > 0) {
        // Show error dialog
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Cannot Delete Item'),
              content: Text(
                'This item is being used in $billCount bill${billCount == 1 ? '' : 's'}. '
                'Items that are used in bills cannot be deleted.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // No bills using it, show confirmation dialog
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Item'),
          content: Text('Are you sure you want to delete "${item.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _deleteItem(item);
      }
    } catch (e) {
      // Clear loading state on error
      setState(() {
        _checkingDeleteItemCode = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteItem(ItemModel item) async {
    try {
      final userDocumentId = await _getUserDocumentId();

      if (userDocumentId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User document not found')),
          );
        }
        return;
      }

      // Find item document by code
      final itemsQuery = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('items')
          .where('code', isEqualTo: item.code)
          .limit(1)
          .get();

      if (itemsQuery.docs.isNotEmpty) {
        // Delete the document
        await itemsQuery.docs.first.reference.delete();
      } else {
        // Try using code as document ID
        await _firestore
            .collection('users')
            .doc(userDocumentId)
            .collection('items')
            .doc(item.code)
            .delete();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchItems();
      }
    } catch (e) {
      debugPrint('Error deleting item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
