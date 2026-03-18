import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/bill_model.dart';

class BillsScreen extends StatefulWidget {
  final String userId;

  const BillsScreen({super.key, required this.userId});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  String? _errorMessage;
  List<BillModel> _bills = [];
  String? _userDocumentId;
  Map<String, String> _billDocIds = {}; // Map billCode to document ID

  @override
  void initState() {
    super.initState();
    _fetchBills();
  }

  Future<void> _fetchBills() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('Fetching bills for user: ${widget.userId}');

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

      _userDocumentId = userDocumentId;

      // Fetch bills from users/{userDocumentId}/bills subcollection
      debugPrint('Fetching bills from users/$userDocumentId/bills');

      final billsSnapshot = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('bills')
          .orderBy('bill_date', descending: true)
          .get();

      debugPrint('Found ${billsSnapshot.docs.length} bills');

      final List<BillModel> allBills = [];
      final Map<String, String> billDocIds = {};

      for (var billDoc in billsSnapshot.docs) {
        try {
          final bill = BillModel.fromFirestore(billDoc);
          allBills.add(bill);
          // Store document ID for each bill code
          billDocIds[bill.billCode] = billDoc.id;
        } catch (e) {
          debugPrint('Error parsing bill ${billDoc.id}: $e');
        }
      }

      setState(() {
        _bills = allBills;
        _billDocIds = billDocIds;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching bills: $e');
      setState(() {
        _errorMessage = 'Error fetching bills: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateBillStatus(BillModel bill, int newStatus) async {
    if (_userDocumentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User document not found')),
      );
      return;
    }

    final billDocId = _billDocIds[bill.billCode];
    if (billDocId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Bill document not found')),
      );
      return;
    }

    try {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Updating bill status...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      // Update bill status in Firestore
      await _firestore
          .collection('users')
          .doc(_userDocumentId)
          .collection('bills')
          .doc(billDocId)
          .update({
            'last_updated_profile': 'ADMIN',
            'completed': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
          });

      // Update local state
      setState(() {
        final index = _bills.indexWhere((b) => b.billCode == bill.billCode);
        if (index != -1) {
          _bills[index] = BillModel(
            id: bill.id,
            billCode: bill.billCode,
            customerCode: bill.customerCode,
            customerName: bill.customerName,
            customerGst: bill.customerGst,
            customerAddress: bill.customerAddress,
            billNo: bill.billNo,
            type: bill.type,
            invoiceNumber: bill.invoiceNumber,
            financialYear: bill.financialYear,
            billDate: bill.billDate,
            billTime: bill.billTime,
            subTotal: bill.subTotal,
            discount: bill.discount,
            grandTotal: bill.grandTotal,
            totalItems: bill.totalItems,
            totalReturnItems: bill.totalReturnItems,
            returnTotal: bill.returnTotal,
            netPayable: bill.netPayable,
            completed: newStatus == 1, // Updated status
            profileId: bill.profileId,
            profileCode: bill.profileCode,
            paymentMode: bill.paymentMode,
            creditAmount: bill.creditAmount,
            additionalInfo: bill.additionalInfo,
            lastUpdatedProfile: bill.lastUpdatedProfile,
            dueDate: bill.dueDate,
            items: bill.items,
            createdAt: bill.createdAt,
            updatedAt: DateTime.now(),
          );
        }
      });

      // Show success message
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bill status updated to ${newStatus == 1 ? 'Completed' : 'Cancelled'}',
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Close the details sheet and refresh
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Error updating bill status: $e');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating bill status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showBillDetails(BillModel bill) {
    // Use items from the bill model (extracted from 'items' JSON field)
    final items = bill.items ?? [];
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
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bill Details',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Invoice: ${bill.invoiceNumber}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
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
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Bill Info Card
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(
                              'Invoice Number',
                              bill.invoiceNumber,
                            ),
                            const SizedBox(height: 8),
                            _buildDetailRow(
                              'Date',
                              DateFormat('dd MMM yyyy').format(bill.billDate),
                            ),
                            const SizedBox(height: 8),
                            _buildDetailRow(
                              'Time',
                              DateFormat('hh:mm a').format(bill.billTime),
                            ),
                            const SizedBox(height: 8),
                            _buildDetailRow('Customer', bill.customerName),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDetailRow(
                                    'Status',
                                    bill.completed ? 'Completed' : 'Cancelled',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    final newStatus = !bill.completed;
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Change Bill Status'),
                                        content: Text(
                                          'Are you sure you want to change the bill status to "${newStatus ? 'Completed' : 'Cancelled'}"?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              _updateBillStatus(
                                                bill,
                                                newStatus ? 1 : 0,
                                              );
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: newStatus
                                                  ? Colors.green
                                                  : Colors.orange,
                                            ),
                                            child: Text(
                                              newStatus
                                                  ? 'Mark as Completed'
                                                  : 'Mark as Cancelled',
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  icon: Icon(
                                    bill.completed
                                        ? Icons.cancel_outlined
                                        : Icons.check_circle_outline,
                                    size: 18,
                                  ),
                                  label: Text(
                                    bill.completed
                                        ? 'Mark Cancelled'
                                        : 'Mark Completed',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: bill.completed
                                        ? Colors.orange[50]
                                        : Colors.green[50],
                                    foregroundColor: bill.completed
                                        ? Colors.orange[800]
                                        : Colors.green[800],
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildDetailRow('Payment Mode', bill.paymentMode),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Items Section
                    Text(
                      'Items (${items.length})',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (items.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No items found',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                        ),
                      )
                    else
                      ...items.map(
                        (item) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Code: ${item.code}'),
                                Text('HSN: ${item.hsnCode}'),
                                Text('Qty: ${item.quantity}'),
                                Text(
                                  'Price: ₹${item.price.toStringAsFixed(2)}',
                                ),
                                Text('Tax: ${item.taxPerc}%'),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₹${item.totalAfterTax.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                if (item.isReturned)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red[100],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Returned',
                                      style: TextStyle(
                                        color: Colors.red[800],
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Summary Card
                    Card(
                      elevation: 2,
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildSummaryRow('Sub Total', bill.subTotal),
                            if (bill.discount > 0)
                              _buildSummaryRow('Discount', -bill.discount),
                            if (bill.returnTotal > 0)
                              _buildSummaryRow(
                                'Return Total',
                                -bill.returnTotal,
                              ),
                            const Divider(),
                            _buildSummaryRow(
                              'Grand Total',
                              bill.grandTotal,
                              isBold: true,
                            ),
                            if (bill.creditAmount > 0)
                              _buildSummaryRow(
                                'Credit Amount',
                                bill.creditAmount,
                              ),
                            _buildSummaryRow(
                              'Net Payable',
                              bill.netPayable,
                              isBold: true,
                              color: Colors.green[700],
                            ),
                          ],
                        ),
                      ),
                    ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(
    String label,
    double amount, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillCard(BillModel bill) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _showBillDetails(bill),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bill.invoiceNumber,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${DateFormat('dd MMM yyyy').format(bill.billDate)} • ${bill.billCode}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: bill.completed
                          ? Colors.green[100]
                          : Colors.orange[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      bill.completed ? 'Completed' : 'Cancelled',
                      style: TextStyle(
                        color: bill.completed
                            ? Colors.green[800]
                            : Colors.orange[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoChip(
                      Icons.shopping_cart,
                      '${bill.totalItems} items',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoChip(
                      Icons.currency_rupee,
                      '₹${bill.grandTotal.toStringAsFixed(2)}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bills'),
            if (!_isLoading && _bills.isNotEmpty)
              Text(
                '${_bills.length} bill${_bills.length == 1 ? '' : 's'}',
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
            onPressed: _fetchBills,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
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
                    onPressed: _fetchBills,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _bills.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No bills found',
                    style: TextStyle(color: Colors.grey[600], fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchBills,
              child: ListView.builder(
                itemCount: _bills.length,
                itemBuilder: (context, index) {
                  return _buildBillCard(_bills[index]);
                },
              ),
            ),
    );
  }
}
