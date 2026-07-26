import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/customer_info_model.dart';
import '../models/service_order_model.dart';
import '../models/service_template_model.dart';
import '../models/sub_profile_model.dart';
import '../utils/item_list_filters.dart';

class _ServiceLocationOption {
  final String id;
  final String name;
  final List<String> subProfileIds;

  const _ServiceLocationOption({
    required this.id,
    required this.name,
    required this.subProfileIds,
  });
}

class ServicesScreen extends StatefulWidget {
  final String userId;

  const ServicesScreen({super.key, required this.userId});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen>
    with SingleTickerProviderStateMixin {
  static const String _defaultLocationFilterValue = '__default_unmapped_profiles__';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final TabController _tabController;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _templateSearchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;

  List<ServiceOrderModel> _orders = [];
  List<ServiceTemplateModel> _templates = [];
  List<CustomerInfoModel> _allCustomers = [];

  String _searchQuery = '';
  String _templateSearchQuery = '';
  bool _showSearchBar = false;

  bool _filterActive = false;
  final Set<ServiceStatus> _appliedStatuses = {};
  String? _appliedCustomerCode;
  DateTime? _appliedDateFrom;
  DateTime? _appliedDateTo;
  String? _appliedLocationId;

  List<_ServiceLocationOption> _locationsForFilter = [];
  final Set<String> _profileIdsMappedToAnyLocation = {};
  final Map<String, String> _profileCodeUpperToId = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _templateSearchController.dispose();
    super.dispose();
  }

  String _normalizeForSearch(String input) {
    final lower = input.trim().toLowerCase();
    final noSpace = lower.replaceAll(RegExp(r'[\s\u00A0]+'), '');
    return noSpace.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _effectiveProfileId(ServiceOrderModel s) {
    final pid = s.profileId.trim();
    if (pid.isNotEmpty) return pid;
    final code = s.profileCode.trim();
    if (code.isEmpty) return '';
    return _profileCodeUpperToId[code.toUpperCase()] ?? '';
  }

  bool _matchesDefaultLocationProfiles(ServiceOrderModel s) {
    final eff = _effectiveProfileId(s);
    if (eff.isEmpty) return true;
    return !_profileIdsMappedToAnyLocation.contains(eff);
  }

  bool _matchesLocationProfiles(ServiceOrderModel s, _ServiceLocationOption loc) {
    final eff = _effectiveProfileId(s);
    if (eff.isEmpty) return false;
    return loc.subProfileIds.contains(eff);
  }

  List<ServiceOrderModel> get _visibleOrders {
    Iterable<ServiceOrderModel> list = _orders;
    if (_filterActive) {
      if (_appliedStatuses.isNotEmpty) {
        list = list.where((s) => _appliedStatuses.contains(s.serviceStatus));
      }
      final cc = _appliedCustomerCode?.trim();
      if (cc != null && cc.isNotEmpty) {
        list = list.where((s) => s.customerCode == cc);
      }
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
        list = list.where((s) {
          final d = DateTime(s.serviceDate.year, s.serviceDate.month, s.serviceDate.day);
          return !d.isBefore(from) && !d.isAfter(to);
        });
      }
      final loc = _appliedLocationId?.trim();
      if (loc != null && loc.isNotEmpty) {
        if (loc == _defaultLocationFilterValue) {
          list = list.where(_matchesDefaultLocationProfiles);
        } else {
          _ServiceLocationOption? chosen;
          for (final o in _locationsForFilter) {
            if (o.id == loc) {
              chosen = o;
              break;
            }
          }
          if (chosen != null) {
            list = list.where((s) => _matchesLocationProfiles(s, chosen!));
          } else {
            list = list.where((_) => false);
          }
        }
      }
    }

    final q = _normalizeForSearch(_searchQuery);
    if (q.isEmpty) return list.toList();
    return list.where((s) {
      final code = _normalizeForSearch(s.serviceCode);
      final number = _normalizeForSearch(s.serviceNumber);
      final customer = _normalizeForSearch(s.customerName);
      return code.contains(q) || number.contains(q) || customer.contains(q);
    }).toList();
  }

  List<ServiceTemplateModel> get _visibleTemplates {
    final q = _templateSearchQuery.trim().toLowerCase();
    if (q.isEmpty) return _templates;
    return _templates.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  ({double advance, double grand, double remaining}) get _todayRevenue {
    final now = DateTime.now();
    var advance = 0.0;
    var grand = 0.0;
    for (final o in _orders) {
      final d = DateTime(o.serviceDate.year, o.serviceDate.month, o.serviceDate.day);
      final today = DateTime(now.year, now.month, now.day);
      if (d == today) {
        advance += o.advanceAmount;
        grand += o.grandTotal;
      }
    }
    final remaining = (grand - advance).clamp(0.0, double.infinity);
    return (advance: advance, grand: grand, remaining: remaining);
  }

  String _customerDisplayName(String code) {
    if (code.trim().isEmpty) return '—';
    for (final c in _allCustomers) {
      if (c.code == code) return c.name.isEmpty ? code : c.name;
    }
    return code;
  }

  String _filterBannerSubtitle() {
    final parts = <String>[];
    if (_appliedStatuses.isNotEmpty) {
      parts.add('Status: ${_appliedStatuses.map((s) => s.label).join(', ')}');
    }
    final cc = _appliedCustomerCode?.trim();
    if (cc != null && cc.isNotEmpty) {
      parts.add('Customer: ${_customerDisplayName(cc)}');
    }
    final loc = _appliedLocationId?.trim();
    if (loc != null && loc.isNotEmpty) {
      if (loc == _defaultLocationFilterValue) {
        parts.add('Location: Default (unmapped profiles)');
      } else {
        var locName = loc;
        for (final l in _locationsForFilter) {
          if (l.id == loc) {
            locName = l.name;
            break;
          }
        }
        parts.add('Location: $locName');
      }
    }
    if (_appliedDateFrom != null || _appliedDateTo != null) {
      final from = _appliedDateFrom != null
          ? DateFormat('dd MMM yyyy').format(_appliedDateFrom!)
          : '…';
      final to = _appliedDateTo != null
          ? DateFormat('dd MMM yyyy').format(_appliedDateTo!)
          : '…';
      parts.add('Date: $from – $to');
    }
    return parts.join(' | ');
  }

  void _clearFilters() {
    setState(() {
      _filterActive = false;
      _appliedStatuses.clear();
      _appliedCustomerCode = null;
      _appliedDateFrom = null;
      _appliedDateTo = null;
      _appliedLocationId = null;
      _searchController.clear();
      _searchQuery = '';
      _showSearchBar = false;
    });
  }

  Future<String?> _resolveUserDocumentId() async {
    final userQuery = await _firestore
        .collection('users')
        .where('userId', isEqualTo: widget.userId)
        .limit(1)
        .get();
    if (userQuery.docs.isNotEmpty) return userQuery.docs.first.id;

    final userDoc = await _firestore.collection('users').doc(widget.userId).get();
    if (userDoc.exists) return widget.userId;
    return null;
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userDocumentId = await _resolveUserDocumentId();
      if (userDocumentId == null) {
        setState(() {
          _errorMessage = 'User document not found';
          _isLoading = false;
        });
        return;
      }
      final ordersFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('service_orders')
          .get();
      final templatesFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('services')
          .get();
      final locationsFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('locations')
          .get();
      final subProfilesFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('subProfiles')
          .get();
      final customerInfoFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('customer_info')
          .get();
      final customersFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('customers')
          .get();

      final results = await Future.wait([
        ordersFuture,
        templatesFuture,
        locationsFuture,
        subProfilesFuture,
        customerInfoFuture,
        customersFuture,
      ]);

      final ordersSnapshot = results[0] as QuerySnapshot;
      final templatesSnapshot = results[1] as QuerySnapshot;
      final locationsSnapshot = results[2] as QuerySnapshot;
      final subProfilesSnapshot = results[3] as QuerySnapshot;
      final customerInfoSnapshot = results[4] as QuerySnapshot;
      final customersSnapshot = results[5] as QuerySnapshot;

      final orders = <ServiceOrderModel>[];
      for (final doc in ordersSnapshot.docs) {
        try {
          orders.add(ServiceOrderModel.fromFirestore(doc));
        } catch (e) {
          debugPrint('Error parsing service order ${doc.id}: $e');
        }
      }
      orders.sort((a, b) => b.serviceDate.compareTo(a.serviceDate));

      final templates = <ServiceTemplateModel>[];
      for (final doc in templatesSnapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) continue;
          templates.add(ServiceTemplateModel.fromFirestore(doc.id, data));
        } catch (e) {
          debugPrint('Error parsing service template ${doc.id}: $e');
        }
      }
      templates.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      _profileIdsMappedToAnyLocation.clear();
      _profileCodeUpperToId.clear();

      final locs = <_ServiceLocationOption>[];
      for (final d in locationsSnapshot.docs) {
        final data = d.data() as Map<String, dynamic>?;
        if (data == null) continue;
        final name = (data['name'] ?? '').toString().trim();
        final rawIds = data['subProfileIds'];
        final subIds = rawIds is List
            ? rawIds.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
            : <String>[];
        for (final id in subIds) {
          _profileIdsMappedToAnyLocation.add(id);
        }
        locs.add(_ServiceLocationOption(
          id: d.id,
          name: name.isEmpty ? d.id : name,
          subProfileIds: subIds,
        ));
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

      final customersByCode = <String, CustomerInfoModel>{};
      for (final d in customerInfoSnapshot.docs) {
        try {
          final c = CustomerInfoModel.fromMap(d.data() as Map<String, dynamic>);
          if (c.code.isNotEmpty) customersByCode[c.code] = c;
        } catch (_) {}
      }
      for (final d in customersSnapshot.docs) {
        try {
          final c = CustomerInfoModel.fromMap(d.data() as Map<String, dynamic>);
          if (c.code.isNotEmpty) customersByCode.putIfAbsent(c.code, () => c);
        } catch (_) {}
      }
      final customersList = customersByCode.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      for (var i = 0; i < orders.length; i++) {
        final o = orders[i];
        if (o.customerName.isEmpty && o.customerCode.isNotEmpty) {
          final c = customersByCode[o.customerCode];
          if (c != null) {
            orders[i] = ServiceOrderModel(
              docId: o.docId,
              id: o.id,
              serviceCode: o.serviceCode,
              customerCode: o.customerCode,
              customerName: c.name,
              customerPhone: c.phone,
              type: o.type,
              status: o.status,
              orderNo: o.orderNo,
              financialYear: o.financialYear,
              serviceNumber: o.serviceNumber,
              serviceDate: o.serviceDate,
              serviceTime: o.serviceTime,
              subTotal: o.subTotal,
              grandTotal: o.grandTotal,
              netPayable: o.netPayable,
              totalItems: o.totalItems,
              profileId: o.profileId,
              profileCode: o.profileCode,
              lastUpdatedProfile: o.lastUpdatedProfile,
              additionalInfo: o.additionalInfo,
              paymentMode: o.paymentMode,
              advanceAmount: o.advanceAmount,
              dueDate: o.dueDate,
              createdAt: o.createdAt,
              updatedAt: o.updatedAt,
              items: o.items,
            );
          }
        }
      }

      setState(() {
        _orders = orders;
        _templates = templates;
        _locationsForFilter = locs;
        _allCustomers = customersList;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching services: $e');
      setState(() {
        _errorMessage = 'Error fetching services: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _showFilterDialog() async {
    final statuses = Set<ServiceStatus>.from(_appliedStatuses);
    String? customerCode = _appliedCustomerCode;
    DateTime? dateFrom = _appliedDateFrom;
    DateTime? dateTo = _appliedDateTo;
    String? locationId = _appliedLocationId;
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
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.filter_list, color: Theme.of(ctx).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Filter Service Orders',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                              'Status',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: ServiceStatus.selectableValues.map((status) {
                                final selected = statuses.contains(status);
                                return FilterChip(
                                  label: Text(status.label),
                                  selected: selected,
                                  onSelected: (val) {
                                    setDialogState(() {
                                      if (val) {
                                        statuses.add(status);
                                      } else {
                                        statuses.remove(status);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Customer',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: customerSearchController,
                              decoration: const InputDecoration(
                                hintText: 'Search customer',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (q) {
                                final n = q.trim().toLowerCase();
                                setDialogState(() {
                                  filteredCustomers = n.isEmpty
                                      ? List<CustomerInfoModel>.from(_allCustomers)
                                      : _allCustomers
                                          .where((c) =>
                                              c.name.toLowerCase().contains(n) ||
                                              c.code.toLowerCase().contains(n) ||
                                              c.phone.toLowerCase().contains(n))
                                          .toList();
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 160,
                              child: ListView.builder(
                                itemCount: filteredCustomers.length + 1,
                                itemBuilder: (_, i) {
                                  if (i == 0) {
                                    return ListTile(
                                      title: const Text('Any customer'),
                                      selected: customerCode == null,
                                      onTap: () => setDialogState(() => customerCode = null),
                                    );
                                  }
                                  final c = filteredCustomers[i - 1];
                                  return ListTile(
                                    title: Text(c.name.isEmpty ? c.code : c.name),
                                    subtitle: Text(c.code),
                                    selected: customerCode == c.code,
                                    onTap: () => setDialogState(() => customerCode = c.code),
                                  );
                                },
                              ),
                            ),
                            if (_locationsForFilter.isNotEmpty) ...[
                              const SizedBox(height: 20),
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
                                    value: locationId,
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
                                    onChanged: (v) => setDialogState(() => locationId = v),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            Text(
                              'Service date range',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: ctx,
                                        initialDate: dateFrom ?? DateTime.now(),
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        setDialogState(() => dateFrom = picked);
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_today, size: 18),
                                    label: Text(
                                      dateFrom != null
                                          ? DateFormat('dd-MM-yyyy').format(dateFrom!)
                                          : 'From date',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: ctx,
                                        initialDate: dateTo ?? dateFrom ?? DateTime.now(),
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        setDialogState(() => dateTo = picked);
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_today, size: 18),
                                    label: Text(
                                      dateTo != null
                                          ? DateFormat('dd-MM-yyyy').format(dateTo!)
                                          : 'To date',
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
                                  statuses.clear();
                                  customerCode = null;
                                  dateFrom = null;
                                  dateTo = null;
                                  locationId = null;
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
                                  _appliedStatuses
                                    ..clear()
                                    ..addAll(statuses);
                                  _appliedCustomerCode = customerCode;
                                  _appliedDateFrom = dateFrom;
                                  _appliedDateTo = dateTo;
                                  _appliedLocationId = locationId?.trim().isEmpty == true
                                      ? null
                                      : locationId?.trim();
                                  _filterActive = _appliedStatuses.isNotEmpty ||
                                      (_appliedCustomerCode?.isNotEmpty ?? false) ||
                                      (_appliedDateFrom != null && _appliedDateTo != null) ||
                                      (_appliedLocationId?.isNotEmpty ?? false);
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

  void _showOrderDetails(ServiceOrderModel order) {
    final items = order.items ?? [];
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
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Service Order',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            order.serviceNumber.isNotEmpty
                                ? order.serviceNumber
                                : order.serviceCode,
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
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
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _detailRow('Service #', order.serviceNumber),
                            _detailRow('Code', order.serviceCode),
                            _detailRow('Status', order.displayStatus),
                            _detailRow(
                              'Date',
                              DateFormat('dd MMM yyyy').format(order.serviceDate),
                            ),
                            _detailRow(
                              'Time',
                              DateFormat('hh:mm a').format(order.serviceTime),
                            ),
                            _detailRow('Customer', order.customerName),
                            _detailRow('Phone', order.customerPhone),
                            _detailRow('Payment', order.paymentMode),
                            _detailRow('Profile', order.profileCode),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Items (${items.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No items in this service order'),
                      )
                    else
                      ...items.map((item) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(item.name),
                            subtitle: Text(
                              '₹${item.price.toStringAsFixed(2)} × ${item.quantity.toStringAsFixed(2)} ${item.unit}',
                            ),
                            trailing: Text(
                              '₹${item.totalAfterTax.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.grey[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _summaryRow('Subtotal', order.subTotal),
                            _summaryRow('Grand Total', order.grandTotal, bold: true),
                            _summaryRow('Advance', order.advanceAmount),
                            _summaryRow(
                              'Net Payable',
                              order.netPayable,
                              bold: true,
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

  void _showTemplateDetails(ServiceTemplateModel template) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(template.name.isEmpty ? 'Service Template' : template.name),
        content: SizedBox(
          width: double.maxFinite,
          child: template.fields.isEmpty
              ? const Text('No fields defined')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: template.fields.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = template.fields[i];
                    return ListTile(
                      dense: true,
                      title: Text(f.name),
                      subtitle: Text(
                        '${f.type}${f.mandatory ? ' • mandatory' : ''}${f.options.isNotEmpty ? ' • ${f.options.length} options' : ''}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double amount, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 16 : 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: bold ? 16 : 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusBg(ServiceStatus status) {
    switch (status) {
      case ServiceStatus.completed:
        return Colors.green[100]!;
      case ServiceStatus.inProgress:
        return Colors.blue[100]!;
      case ServiceStatus.pending:
        return Colors.orange[100]!;
    }
  }

  Color _statusFg(ServiceStatus status) {
    switch (status) {
      case ServiceStatus.completed:
        return Colors.green[800]!;
      case ServiceStatus.inProgress:
        return Colors.blue[800]!;
      case ServiceStatus.pending:
        return Colors.orange[800]!;
    }
  }

  Widget _buildOrderCard(ServiceOrderModel order) {
    final title = order.serviceNumber.isNotEmpty
        ? order.serviceNumber
        : (order.serviceCode.isNotEmpty ? order.serviceCode : '#${order.orderNo}');

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _showOrderDetails(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          order.serviceDate.day.toString().padLeft(2, '0'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          DateFormat('MMM').format(order.serviceDate),
                          style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${order.totalItems} item${order.totalItems == 1 ? '' : 's'}'
                          '${order.customerName.isNotEmpty ? ' • ${order.customerName}' : ''}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${order.grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusBg(order.serviceStatus),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          order.displayStatus,
                          style: TextStyle(
                            color: _statusFg(order.serviceStatus),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRevenueCard() {
    final rev = _todayRevenue;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _revenueStat('Today Advance', rev.advance),
            ),
            Expanded(
              child: _revenueStat('Today Total', rev.grand),
            ),
            Expanded(
              child: _revenueStat('Remaining', rev.remaining),
            ),
          ],
        ),
      ),
    );
  }

  Widget _revenueStat(String label, double value) {
    return Column(
      children: [
        Text(
          '₹${value.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildOrdersTab() {
    final showBanner = _filterActive || _normalizeForSearch(_searchQuery).isNotEmpty;
    final visible = _visibleOrders;

    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.build_circle_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No service orders found',
              style: TextStyle(color: Colors.grey[600], fontSize: 18),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRevenueCard(),
        if (showBanner)
          Material(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _filterActive ? Icons.filter_list : Icons.search,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _filterActive
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
                    onPressed: _clearFilters,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    'No service orders match the current filters or search',
                    style: TextStyle(color: Colors.grey[600], fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchData,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: visible.length,
                    itemBuilder: (_, i) => _buildOrderCard(visible[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTemplatesTab() {
    final visible = _visibleTemplates;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _templateSearchController,
            decoration: InputDecoration(
              hintText: 'Search service templates',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _templateSearchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _templateSearchController.clear();
                        setState(() => _templateSearchQuery = '');
                      },
                    ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (v) => setState(() => _templateSearchQuery = v),
          ),
        ),
        Expanded(
          child: _templates.isEmpty
              ? Center(
                  child: Text(
                    'No service templates found',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                )
              : visible.isEmpty
                  ? Center(
                      child: Text(
                        'No matching templates',
                        style: TextStyle(color: Colors.grey[600], fontSize: 15),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchData,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final t = visible[i];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  (t.name.isNotEmpty ? t.name : 'S').substring(0, 1).toUpperCase(),
                                ),
                              ),
                              title: Text(t.name.isEmpty ? 'Unnamed template' : t.name),
                              subtitle: Text(
                                '${t.fields.length} field${t.fields.length == 1 ? '' : 's'} • Updated ${DateFormat('dd MMM yyyy').format(t.updatedAt)}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _showTemplateDetails(t),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final onOrdersTab = _tabController.index == 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: onOrdersTab && _showSearchBar
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search service code, number or customer',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Services'),
                  if (!_isLoading)
                    Text(
                      onOrdersTab
                          ? (_filterActive || _normalizeForSearch(_searchQuery).isNotEmpty)
                              ? '${_visibleOrders.length} / ${_orders.length} orders'
                              : '${_orders.length} order${_orders.length == 1 ? '' : 's'}'
                          : '${_visibleTemplates.length} template${_visibleTemplates.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                    ),
                ],
              ),
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: 'Service Orders'),
            Tab(text: 'Templates'),
          ],
        ),
        actions: [
          if (onOrdersTab) ...[
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
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => setState(() => _showSearchBar = true),
              ),
              IconButton(
                icon: const Icon(Icons.tune),
                onPressed: _showFilterDialog,
              ),
            ],
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
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
                      Text(_errorMessage!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _fetchData, child: const Text('Retry')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOrdersTab(),
                    _buildTemplatesTab(),
                  ],
                ),
    );
  }
}
