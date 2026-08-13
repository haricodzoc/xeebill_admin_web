import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/bill_model.dart';
import '../models/customer_info_model.dart';
import '../models/sub_profile_model.dart';
import '../models/user_location_model.dart';
import '../utils/item_list_filters.dart';
import 'edit_bill_screen.dart';

class _BillLocationOption {
  final String id;
  final String name;
  /// Sub-profile document IDs mapped to this location (same as `UserLocationsScreen`).
  final List<String> subProfileIds;
  const _BillLocationOption({
    required this.id,
    required this.name,
    required this.subProfileIds,
  });
}

class BillsScreen extends StatefulWidget {
  final String userId;

  const BillsScreen({super.key, required this.userId});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  static const String _defaultLocationFilterValue = '__default_unmapped_profiles__';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String? _errorMessage;
  List<BillModel> _bills = [];
  String? _userDocumentId;
  Map<String, String> _billDocIds = {}; // Map billCode to document ID

  String _searchQuery = '';
  bool _showSearchBar = false;
  bool _billFilterActive = false;
  DateTime? _appliedDateFrom;
  DateTime? _appliedDateTo;
  String? _appliedCustomerCode;
  String? _appliedLocationId;

  List<_BillLocationOption> _locationsForFilter = [];
  List<CustomerInfoModel> _allCustomers = [];

  /// Profile doc ids that appear on at least one location's `subProfileIds`.
  final Set<String> _profileIdsMappedToAnyLocation = {};
  /// When `profile_id` is missing on a bill, resolve via `profile_code` using sub-profiles.
  final Map<String, String> _profileCodeUpperToId = {};

  @override
  void initState() {
    super.initState();
    _fetchBills();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizeForSearch(String input) {
    final lower = input.trim().toLowerCase();
    final noSpace = lower.replaceAll(RegExp(r'[\s\u00A0]+'), '');
    return noSpace.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Resolves sub-profile document id: prefers [BillModel.profileId], then maps [BillModel.profileCode].
  String _effectiveBillProfileId(BillModel b) {
    final pid = b.profileId.trim();
    if (pid.isNotEmpty) return pid;
    final code = b.profileCode.trim();
    if (code.isEmpty) return '';
    return _profileCodeUpperToId[code.toUpperCase()] ?? '';
  }

  bool _billMatchesDefaultLocationProfiles(BillModel b) {
    final eff = _effectiveBillProfileId(b);
    if (eff.isEmpty) return true;
    return !_profileIdsMappedToAnyLocation.contains(eff);
  }

  bool _billMatchesLocationProfiles(BillModel b, _BillLocationOption loc) {
    final eff = _effectiveBillProfileId(b);
    if (eff.isEmpty) return false;
    return loc.subProfileIds.contains(eff);
  }

  List<BillModel> get _visibleBills {
    Iterable<BillModel> list = _bills;
    if (_billFilterActive) {
      if (_appliedDateFrom != null && _appliedDateTo != null) {
        final from = DateTime(
          _appliedDateFrom!.year,
          _appliedDateFrom!.month,
          _appliedDateFrom!.day,
        );
        final to = DateTime(
          _appliedDateTo!.year,
          _appliedDateTo!.month,
          _appliedDateTo!.day,
        );
        list = list.where((b) {
          final d = DateTime(b.billDate.year, b.billDate.month, b.billDate.day);
          return !d.isBefore(from) && !d.isAfter(to);
        });
      }
      final cc = _appliedCustomerCode?.trim();
      if (cc != null && cc.isNotEmpty) {
        list = list.where((b) => b.customerCode == cc);
      }
      final loc = _appliedLocationId?.trim();
      if (loc != null && loc.isNotEmpty) {
        if (loc == _defaultLocationFilterValue) {
          list = list.where(_billMatchesDefaultLocationProfiles);
        } else {
          _BillLocationOption? chosen;
          for (final o in _locationsForFilter) {
            if (o.id == loc) {
              chosen = o;
              break;
            }
          }
          final selectedLoc = chosen;
          if (selectedLoc != null) {
            list = list.where((b) => _billMatchesLocationProfiles(b, selectedLoc));
          } else {
            list = list.where((_) => false);
          }
        }
      }
    }
    final q = _normalizeForSearch(_searchQuery);
    if (q.isEmpty) return list.toList();
    return list.where((b) {
      final inv = _normalizeForSearch(b.invoiceNumber);
      final code = _normalizeForSearch(b.billCode);
      return inv.contains(q) || code.contains(q);
    }).toList();
  }

  String _customerDisplayName(String code) {
    for (final c in _allCustomers) {
      if (c.code == code) return c.name;
    }
    return code;
  }

  String _filterBannerSubtitle() {
    final parts = <String>[];
    if (_billFilterActive &&
        _appliedDateFrom != null &&
        _appliedDateTo != null) {
      parts.add(
        '${DateFormat('dd/MM/yyyy').format(_appliedDateFrom!)} – ${DateFormat('dd/MM/yyyy').format(_appliedDateTo!)}',
      );
    }
    if (_billFilterActive) {
      final cc = _appliedCustomerCode?.trim();
      if (cc != null && cc.isNotEmpty) {
        parts.add('Customer: ${_customerDisplayName(cc)}');
      }
      final loc = _appliedLocationId?.trim();
      if (loc != null && loc.isNotEmpty) {
        if (loc == _defaultLocationFilterValue) {
          parts.add('Location: Default (profiles not mapped to any location)');
        } else {
          String name = loc;
          for (final l in _locationsForFilter) {
            if (l.id == loc) {
              name = l.name;
              break;
            }
          }
          parts.add('Location: $name');
        }
      }
    }
    return parts.join(' | ');
  }

  void _clearBillFilters() {
    setState(() {
      _billFilterActive = false;
      _appliedDateFrom = null;
      _appliedDateTo = null;
      _appliedCustomerCode = null;
      _appliedLocationId = null;
      _searchController.clear();
      _searchQuery = '';
      _showSearchBar = false;
    });
  }

  Future<void> _showFilterBillsDialog() async {
    final now = DateTime.now();
    var dialogDateFrom = _appliedDateFrom ?? DateTime(now.year, now.month, now.day);
    var dialogDateTo = _appliedDateTo ?? DateTime(now.year, now.month, now.day);
    String? dialogCustomerCode = _appliedCustomerCode;
    String? dialogCustomerName =
        dialogCustomerCode != null ? _customerDisplayName(dialogCustomerCode) : null;
    String? dialogLocationId = _appliedLocationId;

    final customerSearchController = TextEditingController();
    var filteredCustomers = List<CustomerInfoModel>.from(_allCustomers);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: SizedBox(
                width: MediaQuery.of(ctx).size.width * 0.9,
                height: MediaQuery.of(ctx).size.height * 0.88,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.filter_list, color: Theme.of(ctx).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Filter Bills',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date range',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: ctx,
                                        initialDate: dialogDateFrom,
                                        firstDate: DateTime(2020),
                                        lastDate: dialogDateTo,
                                      );
                                      if (picked != null) {
                                        setDialogState(() => dialogDateFrom = picked);
                                      }
                                    },
                                    child: Text(
                                      DateFormat('dd/MM/yyyy').format(dialogDateFrom),
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('to'),
                                ),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: ctx,
                                        initialDate: dialogDateTo,
                                        firstDate: dialogDateFrom,
                                        lastDate: DateTime.now(),
                                      );
                                      if (picked != null) {
                                        setDialogState(() => dialogDateTo = picked);
                                      }
                                    },
                                    child: Text(
                                      DateFormat('dd/MM/yyyy').format(dialogDateTo),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Customer',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: customerSearchController,
                              decoration: InputDecoration(
                                hintText: 'Search by name or phone',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                isDense: true,
                              ),
                              onChanged: (value) {
                                setDialogState(() {
                                  final q = value.trim().toLowerCase();
                                  if (q.isEmpty) {
                                    filteredCustomers = List<CustomerInfoModel>.from(_allCustomers);
                                  } else {
                                    filteredCustomers = _allCustomers
                                        .where(
                                          (c) =>
                                              c.name.toLowerCase().contains(q) ||
                                              c.phone.toLowerCase().contains(q),
                                        )
                                        .toList();
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            if (dialogCustomerName != null)
                              Material(
                                color: Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(8),
                                child: ListTile(
                                  title: Text(dialogCustomerName ?? ''),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () {
                                      setDialogState(() {
                                        dialogCustomerCode = null;
                                        dialogCustomerName = null;
                                        customerSearchController.clear();
                                        filteredCustomers = List<CustomerInfoModel>.from(_allCustomers);
                                      });
                                    },
                                  ),
                                ),
                              )
                            else
                              Container(
                                constraints: const BoxConstraints(maxHeight: 200),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Theme.of(ctx).dividerColor),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: filteredCustomers.isEmpty
                                    ? const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Text('No customers found'),
                                        ),
                                      )
                                    : ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: filteredCustomers.length,
                                        itemBuilder: (context, index) {
                                          final customer = filteredCustomers[index];
                                          return ListTile(
                                            dense: true,
                                            title: Text(customer.name),
                                            subtitle: Text(customer.phone),
                                            onTap: () {
                                              setDialogState(() {
                                                dialogCustomerCode = customer.code;
                                                dialogCustomerName = customer.name;
                                                customerSearchController.clear();
                                              });
                                            },
                                          );
                                        },
                                      ),
                              ),
                            if (_locationsForFilter.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              Text(
                                'Location',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(ctx).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              InputDecorator(
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    isExpanded: true,
                                    value: dialogLocationId,
                                    hint: const Text('All locations'),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('All locations'),
                                      ),
                                      DropdownMenuItem<String?>(
                                        value: _defaultLocationFilterValue,
                                        child: const Text(
                                          'Default — profiles not mapped to any location',
                                        ),
                                      ),
                                      ..._locationsForFilter.map(
                                        (l) => DropdownMenuItem<String?>(
                                          value: l.id,
                                          child: Text(l.name),
                                        ),
                                      ),
                                    ],
                                    onChanged: (v) => setDialogState(() => dialogLocationId = v),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setDialogState(() {
                                  final n = DateTime.now();
                                  dialogDateFrom = DateTime(n.year, n.month, n.day);
                                  dialogDateTo = DateTime(n.year, n.month, n.day);
                                  dialogCustomerCode = null;
                                  dialogCustomerName = null;
                                  dialogLocationId = null;
                                  customerSearchController.clear();
                                  filteredCustomers = List<CustomerInfoModel>.from(_allCustomers);
                                });
                              },
                              child: const Text('Clear'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  _appliedDateFrom = dialogDateFrom;
                                  _appliedDateTo = dialogDateTo;
                                  _appliedCustomerCode = dialogCustomerCode;
                                  _appliedLocationId = dialogLocationId?.trim().isEmpty == true
                                      ? null
                                      : dialogLocationId?.trim();
                                  _billFilterActive = true;
                                });
                                Navigator.pop(ctx);
                              },
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    customerSearchController.dispose();
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

      // Fetch bills, locations, and customers in parallel
      debugPrint('Fetching bills/locations/customers from users/$userDocumentId');

      final billsFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('bills')
          .orderBy('bill_date', descending: true)
          .get();
      final locationsFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('locations')
          .get();
      final customersFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('customers')
          .get();
      final subProfilesFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('subProfiles')
          .get();

      final results = await Future.wait([
        billsFuture,
        locationsFuture,
        customersFuture,
        subProfilesFuture,
      ]);
      final billsSnapshot = results[0] as QuerySnapshot;
      final locationsSnapshot = results[1] as QuerySnapshot;
      final customersSnapshot = results[2] as QuerySnapshot;
      final subProfilesSnapshot = results[3] as QuerySnapshot;

      debugPrint('Found ${billsSnapshot.docs.length} bills');

      final List<BillModel> allBills = [];
      final Map<String, String> billDocIds = {};

      for (var billDoc in billsSnapshot.docs) {
        try {
          final bill = BillModel.fromFirestore(billDoc);
          allBills.add(bill);
          billDocIds[bill.billCode] = billDoc.id;
        } catch (e) {
          debugPrint('Error parsing bill ${billDoc.id}: $e');
        }
      }

      _profileIdsMappedToAnyLocation.clear();
      _profileCodeUpperToId.clear();

      final List<_BillLocationOption> locs = [];
      for (final d in locationsSnapshot.docs) {
        try {
          final ul = UserLocationModel.fromFirestore(
            d as DocumentSnapshot<Map<String, dynamic>>,
          );
          for (final pid in ul.subProfileIds) {
            _profileIdsMappedToAnyLocation.add(pid);
          }
          final name = ul.name.trim();
          locs.add(
            _BillLocationOption(
              id: ul.id,
              name: name.isEmpty ? ul.id : name,
              subProfileIds: List<String>.from(ul.subProfileIds),
            ),
          );
        } catch (e) {
          debugPrint('Error parsing location ${d.id}: $e');
        }
      }
      locs.sort((a, b) => naturalSortComparator(a.name, b.name));

      for (final d in subProfilesSnapshot.docs) {
        try {
          final data = d.data() as Map<String, dynamic>?;
          if (data == null) continue;
          final sp = SubProfileModel.fromMap(data, d.id);
          final code = sp.code.trim();
          if (code.isNotEmpty) {
            _profileCodeUpperToId[code.toUpperCase()] = sp.id;
          }
        } catch (e) {
          debugPrint('Error parsing sub profile ${d.id}: $e');
        }
      }

      final List<CustomerInfoModel> customersList = [];
      for (final d in customersSnapshot.docs) {
        try {
          final raw = d.data() as Map<String, dynamic>?;
          if (raw == null) continue;
          final data = Map<String, dynamic>.from(raw);
          final code = (data['code'] ?? '').toString().trim();
          if (code.isEmpty) {
            data['code'] = d.id;
          }
          customersList.add(CustomerInfoModel.fromMap(data));
        } catch (e) {
          debugPrint('Error parsing customer ${d.id}: $e');
        }
      }
      customersList.sort((a, b) => naturalSortComparator(a.name, b.name));

      setState(() {
        _bills = allBills;
        _billDocIds = billDocIds;
        _locationsForFilter = locs;
        _allCustomers = customersList;
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
            'completed': 1,
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
            locationId: bill.locationId,
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
    final items = bill.items ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
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
                      tooltip: 'Edit bill',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final userDocId = _userDocumentId;
                        final billDocId = _billDocIds[bill.billCode];
                        if (userDocId == null || billDocId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Bill document not found'),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(context);
                        final saved = await Navigator.push<bool>(
                          this.context,
                          MaterialPageRoute(
                            builder: (_) => EditBillScreen(
                              userDocumentId: userDocId,
                              billDocId: billDocId,
                              bill: bill,
                            ),
                          ),
                        );
                        if (saved == true && mounted) {
                          await _fetchBills();
                        }
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
                            const SizedBox(height: 8),
                            _buildDetailRow(
                              'Updated At',
                              DateFormat('dd MMM yyyy, hh:mm a')
                                  .format(bill.updatedAt),
                            ),
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
                      ...List.generate(items.length, (index) {
                        final item = items[index];
                        return Card(
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
                                Text(
                                  'Tax: ${item.taxPerc.toStringAsFixed(2)}%',
                                ),
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
                        );
                      }),
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
    final showBanner = _billFilterActive || _normalizeForSearch(_searchQuery).isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: _showSearchBar
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search invoice or bill code',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bills'),
                  if (!_isLoading && _bills.isNotEmpty)
                    Text(
                      (_billFilterActive || _normalizeForSearch(_searchQuery).isNotEmpty)
                          ? '${_visibleBills.length} / ${_bills.length} bills'
                          : '${_bills.length} bill${_bills.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                ],
              ),
        actions: [
          if (_showSearchBar)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _showSearchBar = false;
                  _searchController.clear();
                  _searchQuery = '';
                });
              },
              tooltip: 'Close search',
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _showSearchBar = true),
              tooltip: 'Search',
            ),
            IconButton(
              icon: const Icon(Icons.tune),
              onPressed: _showFilterBillsDialog,
              tooltip: 'Filter bills',
            ),
          ],
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showBanner)
                  Material(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            _billFilterActive ? Icons.filter_list : Icons.search,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _billFilterActive
                                  ? _filterBannerSubtitle()
                                  : 'Search: "${_searchController.text}"',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: 'Clear',
                            onPressed: _clearBillFilters,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: _visibleBills.isEmpty
                      ? Center(
                          child: Text(
                            _billFilterActive || _normalizeForSearch(_searchQuery).isNotEmpty
                                ? 'No bills match the current filters or search'
                                : 'No bills found',
                            style: TextStyle(color: Colors.grey[600], fontSize: 15),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchBills,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: _visibleBills.length,
                            itemBuilder: (context, index) {
                              return _buildBillCard(_visibleBills[index]);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
