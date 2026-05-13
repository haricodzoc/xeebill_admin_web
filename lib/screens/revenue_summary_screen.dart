import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill_model.dart';
import '../models/sub_profile_model.dart';
import '../models/user_location_model.dart';
import '../utils/constants.dart';
import '../utils/item_list_filters.dart';

String _lastTwoChars(String code) {
  final t = code.trim();
  if (t.isEmpty) return '';
  if (t.length <= 2) return t.toUpperCase();
  return t.substring(t.length - 2).toUpperCase();
}

String _profileKeyFromCode(String code) {
  final c = code.trim();
  if (c.isEmpty) return '';
  return c.length <= 2 ? c.toUpperCase() : _lastTwoChars(c);
}

/// Matches [bill.profileCode]'s last two characters to each mapped subprofile [code].
bool _billBelongsToLocation(BillModel bill, List<SubProfileModel> mappedProfiles) {
  if (mappedProfiles.isEmpty) return false;
  final fromBill = _lastTwoChars(bill.profileCode);
  if (fromBill.isEmpty) return false;
  for (final p in mappedProfiles) {
    final c = p.code.trim();
    if (c.isEmpty) continue;
    final profileKey = c.length <= 2 ? c.toUpperCase() : _lastTwoChars(c);
    if (fromBill == profileKey) return true;
  }
  return false;
}

bool _isMpOrSaSuffix(String twoCharSuffix) {
  final s = twoCharSuffix.toUpperCase();
  return s == 'MP' || s == 'SA';
}

/// Bills whose [BillModel.profileCode] last two characters are MP or SA.
bool _billBelongsToDefaultLocation(BillModel bill) {
  return _isMpOrSaSuffix(_lastTwoChars(bill.profileCode));
}

({double totalSales, double totalReturns}) _totalsForBills(List<BillModel> bills) {
  double totalSales = 0;
  double totalReturns = 0;
  final saleReturnType = GstType.saleReturn.toString();
  for (final b in bills) {
    if (b.type == saleReturnType) {
      totalReturns += b.subTotal.abs();
    } else {
      totalSales += b.netPayable == 0 ? b.grandTotal : b.netPayable;
    }
  }
  return (totalSales: totalSales, totalReturns: totalReturns);
}

String _formatMoney(double v) => v.toStringAsFixed(2);

Map<String, dynamic> _additionalInfoMap(BillModel bill) {
  final s = bill.additionalInfo.trim();
  if (s.isEmpty) return {};
  try {
    final decoded = jsonDecode(s);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return {};
}

PaymentModes _paymentModeFromString(String raw) {
  final s = raw.trim();
  for (final m in PaymentModes.values) {
    if (m.toString() == s) return m;
  }
  final lower = s.toLowerCase();
  if (lower.contains('multi')) return PaymentModes.multiPay;
  if (lower.contains('credit')) return PaymentModes.credit;
  if (lower.contains('card')) return PaymentModes.card;
  if (lower.contains('upi')) return PaymentModes.upi;
  if (lower.contains('wallet')) return PaymentModes.wallet;
  if (lower.contains('cheque')) return PaymentModes.cheque;
  return PaymentModes.cash;
}

Map<String, double> _allocatePaymentSplit(BillModel bill, double totalAmount) {
  final split = <String, double>{};
  if (totalAmount <= 0) return split;
  final mode = _paymentModeFromString(bill.paymentMode);
  final infoMap = _additionalInfoMap(bill);
  final dynamic additional = infoMap['additional_payment_info'];

  void add(String k, double v) {
    if (v <= 0) return;
    split[k] = (split[k] ?? 0) + v;
  }

  if (mode == PaymentModes.multiPay && additional is List) {
    final rows = additional
        .whereType<Map>()
        .map((e) {
          final key = (e['payment_mode'] ?? e['mode'] ?? 'cash').toString().toLowerCase();
          final amtRaw = e['amount'];
          final amt = amtRaw is num ? amtRaw.toDouble() : double.tryParse(amtRaw.toString()) ?? 0;
          return (key: key, amount: amt);
        })
        .where((r) => r.amount > 0)
        .toList();

    final sum = rows.fold<double>(0, (s, r) => s + r.amount);
    if (rows.isNotEmpty && sum > 0) {
      for (final r in rows) {
        add(r.key, (r.amount / sum) * totalAmount);
      }
      return split;
    }
  }

  if (mode == PaymentModes.credit) {
    final creditPart = bill.creditAmount.clamp(0, totalAmount).toDouble();
    add('credit', creditPart);
    final remaining = (totalAmount - creditPart).clamp(0, totalAmount).toDouble();
    String remainingMode = 'cash';
    if (additional is List && additional.isNotEmpty) {
      final first = additional.first;
      if (first is Map) {
        remainingMode = (first['payment_mode'] ?? first['mode'] ?? 'cash').toString().toLowerCase();
      }
    }
    add(remainingMode, remaining);
    return split;
  }

  add(mode.name, totalAmount);
  return split;
}

Map<String, double> _paymentSplitForBills(List<BillModel> bills, {required bool forReturns}) {
  final out = <String, double>{};
  final saleReturnType = GstType.saleReturn.toString();
  for (final b in bills) {
    final isReturn = b.type == saleReturnType;
    if (forReturns != isReturn) continue;
    final amount = isReturn ? b.subTotal.abs() : (b.netPayable == 0 ? b.grandTotal : b.netPayable);
    final split = _allocatePaymentSplit(b, amount);
    for (final e in split.entries) {
      out[e.key] = (out[e.key] ?? 0) + e.value;
    }
  }
  return out;
}

void _showPaymentSplitModal(
  BuildContext context, {
  required String title,
  required Map<String, double> split,
  required Color color,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final entries = split.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final titleStyle = Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
      final bodyStyle = Theme.of(ctx).textTheme.bodyMedium;
      final muted = Theme.of(ctx).colorScheme.onSurfaceVariant;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle),
              const SizedBox(height: 10),
              if (entries.isEmpty)
                Text('No payment split data found.', style: bodyStyle?.copyWith(color: muted))
              else
                ...entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key.toUpperCase(),
                            style: bodyStyle?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '₹${_formatMoney(e.value)}',
                          style: bodyStyle?.copyWith(fontWeight: FontWeight.w700, color: color),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

Future<String?> _resolveUserDocumentId(FirebaseFirestore firestore, String userId) async {
  final userQuery = await firestore.collection('users').where('userId', isEqualTo: userId).limit(1).get();
  if (userQuery.docs.isNotEmpty) {
    return userQuery.docs.first.id;
  }
  final userDoc = await firestore.collection('users').doc(userId).get();
  if (userDoc.exists) {
    return userId;
  }
  return null;
}

/// Same calendar day as mobile `getBillsForDate` (local timezone).
bool _sameCalendarDayLocal(DateTime billInstant, DateTime selectedDay) {
  final want = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
  final local = billInstant.toLocal();
  final got = DateTime(local.year, local.month, local.day);
  return got == want;
}

/// Loads bills like [BillsScreen], then filters by selected day. Firestore often stores
/// `bill_date` as ISO strings; range queries with [Timestamp] return no rows for those docs.
Future<List<BillModel>> _fetchBillsForDate(FirebaseFirestore firestore, String userDocumentId, DateTime day) async {
  Query<Map<String, dynamic>> ordered(String field) {
    return firestore
        .collection('users')
        .doc(userDocumentId)
        .collection('bills')
        .orderBy(field, descending: true);
  }

  QuerySnapshot<Map<String, dynamic>> snap;
  try {
    snap = await ordered('bill_date').get();
  } catch (e) {
    debugPrint('Revenue summary orderBy bill_date failed: $e');
    try {
      snap = await ordered('billDate').get();
    } catch (e2) {
      debugPrint('Revenue summary orderBy billDate failed: $e2');
      snap = await firestore.collection('users').doc(userDocumentId).collection('bills').get();
    }
  }

  final list = <BillModel>[];
  for (final d in snap.docs) {
    try {
      final b = BillModel.fromFirestore(d);
      if (_sameCalendarDayLocal(b.billDate, day)) {
        list.add(b);
      }
    } catch (_) {}
  }
  list.sort((a, b) {
    final byDate = b.billDate.compareTo(a.billDate);
    if (byDate != 0) return byDate;
    return b.billNo.compareTo(a.billNo);
  });
  return list;
}

/// Revenue summary for a single user account (Firestore), matching mobile layout & calculations.
class RevenueSummaryScreen extends StatefulWidget {
  final String userId;

  const RevenueSummaryScreen({super.key, required this.userId});

  @override
  State<RevenueSummaryScreen> createState() => _RevenueSummaryScreenState();
}

class _RevenueSummaryScreenState extends State<RevenueSummaryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late DateTime _selectedDate;
  late DateTime _appliedDate;
  Future<List<BillModel>>? _billsForDateFuture;

  bool _loadingMeta = true;
  String? _errorMeta;
  String? _userDocumentId;
  List<SubProfileModel> _subProfiles = [];
  List<UserLocationModel> _locations = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _appliedDate = _selectedDate;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loadingMeta = true;
      _errorMeta = null;
    });
    try {
      final uid = await _resolveUserDocumentId(_firestore, widget.userId);
      if (uid == null) {
        setState(() {
          _loadingMeta = false;
          _errorMeta = 'User document not found';
        });
        return;
      }
      final locSnap = _firestore.collection('users').doc(uid).collection('locations').get();
      final spSnap = _firestore.collection('users').doc(uid).collection('subProfiles').get();
      final results = await Future.wait([locSnap, spSnap]);

      final locations = <UserLocationModel>[];
      for (final d in (results[0] as QuerySnapshot).docs) {
        try {
          locations.add(UserLocationModel.fromFirestore(d as DocumentSnapshot<Map<String, dynamic>>));
        } catch (_) {}
      }
      locations.sort((a, b) => naturalSortComparator(a.name, b.name));

      final profiles = <SubProfileModel>[];
      for (final d in (results[1] as QuerySnapshot).docs) {
        try {
          final data = d.data() as Map<String, dynamic>?;
          if (data == null) continue;
          profiles.add(SubProfileModel.fromMap(data, d.id));
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _userDocumentId = uid;
        _locations = locations;
        _subProfiles = profiles;
        _loadingMeta = false;
        _billsForDateFuture = _fetchBillsForDate(_firestore, uid, _appliedDate);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMeta = false;
        _errorMeta = '$e';
      });
    }
  }

  List<SubProfileModel> _profilesForLocation(UserLocationModel location, List<SubProfileModel> all) {
    final byId = {for (final p in all) p.id: p};
    return location.subProfileIds.map((id) => byId[id]).whereType<SubProfileModel>().toList();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  void _applyDateAndReload() {
    final uid = _userDocumentId;
    if (uid == null) return;
    setState(() {
      _appliedDate = _selectedDate;
      _billsForDateFuture = _fetchBillsForDate(_firestore, uid, _appliedDate);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gradient = LinearGradient(
      colors: [cs.primary, cs.primary.withValues(alpha: 0.85)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    if (_errorMeta != null && _userDocumentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Revenue Summary')),
        body: Center(child: Text(_errorMeta!)),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Revenue Summary'),
        surfaceTintColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 20, color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Date',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('EEE, d MMM yyyy').format(_selectedDate),
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _applyDateAndReload,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('View'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<BillModel>>(
              future: _billsForDateFuture,
              builder: (context, snap) {
                if (_loadingMeta ||
                    _billsForDateFuture == null ||
                    snap.connectionState == ConnectionState.waiting ||
                    snap.connectionState == ConnectionState.none) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                    ),
                  );
                }
                final bills = snap.data ?? [];
                final totals = _totalsForBills(bills);
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ALL BILLS · ${DateFormat('d MMM yyyy').format(_appliedDate)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total sales',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₹${_formatMoney(totals.totalSales)}',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total returns',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₹${_formatMoney(totals.totalReturns)}',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loadingMeta
                  ? const Center(child: CircularProgressIndicator())
                  : FutureBuilder<List<BillModel>>(
                      future: _billsForDateFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final allBills = snapshot.data ?? [];
                        final bool hasAnyMappedSubprofileInLocations =
                            _locations.any((l) => l.subProfileIds.isNotEmpty);

                        final Set<String> subProfileIdsMappedToAnyLocation = {};
                        for (final loc in _locations) {
                          subProfileIdsMappedToAnyLocation.addAll(loc.subProfileIds);
                        }
                        final List<SubProfileModel> profilesNotMappedToAnyLocation = _subProfiles
                            .where((p) => p.id.isNotEmpty && !subProfileIdsMappedToAnyLocation.contains(p.id))
                            .toList();

                        List<SubProfileModel> defaultProfiles;
                        final List<BillModel> defaultBills;
                        final String defaultSubtitle;
                        final String defaultEmptyProfilesMessage;

                        if (!hasAnyMappedSubprofileInLocations) {
                          defaultProfiles = List<SubProfileModel>.from(_subProfiles);

                          final bool hasMp = defaultProfiles.any((p) => _profileKeyFromCode(p.code) == 'MP');
                          if (!hasMp) {
                            defaultProfiles.add(SubProfileModel(
                              id: 'MP',
                              name: 'MP',
                              code: 'MP',
                              prefix: '',
                              avatar: '',
                              pin: '',
                              status: '',
                            ));
                          }

                          final byKey = <String, SubProfileModel>{};
                          for (final p in defaultProfiles) {
                            final k = _profileKeyFromCode(p.code);
                            if (k.isEmpty) continue;
                            byKey[k] = p;
                          }
                          defaultProfiles = byKey.values.toList();
                          defaultBills = allBills.where((b) => _billBelongsToLocation(b, defaultProfiles)).toList()
                            ..sort((a, b) {
                              final byDate = b.billDate.compareTo(a.billDate);
                              if (byDate != 0) return byDate;
                              return b.billNo.compareTo(a.billNo);
                            });

                          defaultSubtitle = 'All profiles';
                          defaultEmptyProfilesMessage = 'No subprofiles in account.';
                        } else {
                          defaultProfiles = List<SubProfileModel>.from(profilesNotMappedToAnyLocation);

                          final bool hasMp = defaultProfiles.any((p) => _profileKeyFromCode(p.code) == 'MP');
                          if (!hasMp) {
                            defaultProfiles.add(SubProfileModel(
                              id: 'MP',
                              name: 'MP',
                              code: 'MP',
                              prefix: '',
                              avatar: '',
                              pin: '',
                              status: '',
                            ));
                          }

                          final defaultByKey = <String, SubProfileModel>{};
                          for (final p in defaultProfiles) {
                            final k = _profileKeyFromCode(p.code);
                            if (k.isEmpty) continue;
                            defaultByKey[k] = p;
                          }
                          defaultProfiles = defaultByKey.values.toList();

                          defaultBills = allBills
                              .where(
                                (b) => _billBelongsToDefaultLocation(b) || _billBelongsToLocation(b, defaultProfiles),
                              )
                              .toList()
                            ..sort((a, b) {
                              final byDate = b.billDate.compareTo(a.billDate);
                              if (byDate != 0) return byDate;
                              return b.billNo.compareTo(a.billNo);
                            });

                          defaultSubtitle = profilesNotMappedToAnyLocation.isEmpty
                              ? 'Main Location'
                              : 'Main location · ${profilesNotMappedToAnyLocation.length} not assigned';
                          defaultEmptyProfilesMessage = 'No profiles to show.';
                        }
                        final locCount = _locations.length;
                        return ListView.builder(
                          itemCount: 1 + locCount,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ExpandableLocationCard(
                                  title: 'Default',
                                  subtitle: defaultSubtitle,
                                  leadingIcon: Icons.home_work_outlined,
                                  mappedProfiles: defaultProfiles,
                                  todaysBills: defaultBills,
                                  emptyProfilesMessage: defaultEmptyProfilesMessage,
                                  allowBillsWithoutMappedProfiles: true,
                                ),
                              );
                            }
                            final location = _locations[index - 1];
                            final mapped = _profilesForLocation(location, _subProfiles);
                            final billsHere = allBills.where((b) => _billBelongsToLocation(b, mapped)).toList()
                              ..sort((a, b) {
                                final byDate = b.billDate.compareTo(a.billDate);
                                if (byDate != 0) return byDate;
                                return b.billNo.compareTo(a.billNo);
                              });
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ExpandableLocationCard(
                                title: location.name,
                                subtitle: '${mapped.length} mapped profile${mapped.length == 1 ? '' : 's'}',
                                leadingIcon: Icons.place_outlined,
                                mappedProfiles: mapped,
                                todaysBills: billsHere,
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableLocationCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData leadingIcon;
  final List<SubProfileModel> mappedProfiles;
  final List<BillModel> todaysBills;
  final String emptyProfilesMessage;
  final bool allowBillsWithoutMappedProfiles;

  const _ExpandableLocationCard({
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.mappedProfiles,
    required this.todaysBills,
    this.emptyProfilesMessage = 'No profiles mapped to this location.',
    this.allowBillsWithoutMappedProfiles = false,
  });

  @override
  State<_ExpandableLocationCard> createState() => _ExpandableLocationCardState();
}

class _ExpandableLocationCardState extends State<_ExpandableLocationCard> {
  late Set<String> _selectedProfileIds;

  @override
  void initState() {
    super.initState();
    _selectedProfileIds = widget.mappedProfiles.map((p) => p.id).toSet();
  }

  @override
  void didUpdateWidget(covariant _ExpandableLocationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mappedProfiles.length != widget.mappedProfiles.length) {
      _selectedProfileIds = widget.mappedProfiles.map((p) => p.id).toSet();
    }
  }

  List<SubProfileModel> get selectedProfiles {
    return widget.mappedProfiles.where((p) => _selectedProfileIds.contains(p.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalCount = widget.mappedProfiles.length;
    final selectedCount = _selectedProfileIds.length;
    final subtitleText = totalCount == 0
        ? widget.subtitle
        : '${widget.subtitle.isEmpty ? '' : '${widget.subtitle} • '}$selectedCount/$totalCount selected';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Icon(widget.leadingIcon, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(left: 28, top: 4),
            child: Text(
              subtitleText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          children: [
            _SectionCard(
              title: 'Profiles',
              child: widget.mappedProfiles.isEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            widget.emptyProfilesMessage,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                        Text(
                          'Select profiles to filter bills & totals.',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.mappedProfiles.map((p) {
                            final isSelected = _selectedProfileIds.contains(p.id);
                            final codeKey = _profileKeyFromCode(p.code);
                            return FilterChip(
                              label: Text(
                                '${p.name} (${codeKey.isEmpty ? p.code : codeKey})',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              selected: isSelected,
                              onSelected: (val) {
                                setState(() {
                                  if (val) {
                                    _selectedProfileIds.add(p.id);
                                  } else {
                                    _selectedProfileIds.remove(p.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Tap to select/deselect for filtering.',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            _SectionCard(
              title: 'Bills',
              child: _LocationBillsBody(
                selectedProfiles: selectedProfiles,
                bills: widget.todaysBills,
                allowBillsWithoutMappedProfiles: widget.allowBillsWithoutMappedProfiles,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _LocationBillsBody extends StatelessWidget {
  final List<SubProfileModel> selectedProfiles;
  final List<BillModel> bills;
  final bool allowBillsWithoutMappedProfiles;

  const _LocationBillsBody({
    required this.selectedProfiles,
    required this.bills,
    this.allowBillsWithoutMappedProfiles = false,
  });

  void _showBillPeek(BuildContext context, BillModel bill) {
    final saleReturnType = GstType.saleReturn.toString();
    final isSaleReturn = bill.type == saleReturnType;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bill #${bill.invoiceNumber}',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Customer: ${bill.customerName.isEmpty ? bill.customerCode : bill.customerName}'),
              Text('Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(bill.billDate)}'),
              Text('Type: ${isSaleReturn ? 'Sale Return' : 'Regular'}'),
              Text('Payment: ${bill.paymentMode}'),
              const SizedBox(height: 8),
              Text(
                'Amount: ₹${_formatMoney(isSaleReturn ? -bill.subTotal.abs() : (bill.netPayable == 0 ? bill.grandTotal : bill.netPayable))}',
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final success = Colors.green.shade700;
    final successBg = Colors.green.shade50;
    final err = cs.error;
    final errBg = cs.errorContainer;

    final filteredBills = selectedProfiles.isEmpty
        ? <BillModel>[]
        : bills.where((b) => _billBelongsToLocation(b, selectedProfiles)).toList()
      ..sort((a, b) {
        final byDate = b.billDate.compareTo(a.billDate);
        if (byDate != 0) return byDate;
        return b.billNo.compareTo(a.billNo);
      });

    final totals = _totalsForBills(filteredBills);
    final salesSplit = _paymentSplitForBills(filteredBills, forReturns: false);
    final returnsSplit = _paymentSplitForBills(filteredBills, forReturns: true);
    final revenueByPayment = <String, double>{};
    for (final e in salesSplit.entries) {
      revenueByPayment[e.key] = (revenueByPayment[e.key] ?? 0) + e.value;
    }
    for (final e in returnsSplit.entries) {
      revenueByPayment[e.key] = (revenueByPayment[e.key] ?? 0) - e.value;
    }
    final revenueEntries = revenueByPayment.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    const radiusLg = 12.0;
    const radiusMd = 8.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _showPaymentSplitModal(
                  context,
                  title: 'Sales Split by Payment Mode',
                  split: salesSplit,
                  color: success,
                ),
                borderRadius: BorderRadius.circular(radiusLg),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: successBg,
                    borderRadius: BorderRadius.circular(radiusLg),
                    border: Border.all(color: success.withValues(alpha: 0.18)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Sales',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: success, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${_formatMoney(totals.totalSales)}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: success,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => _showPaymentSplitModal(
                  context,
                  title: 'Returns Split by Payment Mode',
                  split: returnsSplit,
                  color: err,
                ),
                borderRadius: BorderRadius.circular(radiusLg),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: errBg.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(radiusLg),
                    border: Border.all(color: err.withValues(alpha: 0.16)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Returns',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: err, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '- ₹${_formatMoney(totals.totalReturns)}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: err,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(radiusLg),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Revenue by Payment Mode',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              if (revenueEntries.isEmpty)
                Text(
                  'No payment revenue data.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: revenueEntries
                      .map(
                        (e) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(radiusMd),
                            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.8)),
                          ),
                          child: Text(
                            '${e.key.toUpperCase()}: ₹${_formatMoney(e.value)}',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (filteredBills.isEmpty)
          Text(
            allowBillsWithoutMappedProfiles ? 'No bills for selected profiles.' : 'No bills for selected profiles.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredBills.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final bill = filteredBills[index];
              final saleReturnType = GstType.saleReturn.toString();
              final bool isSaleReturn = bill.type == saleReturnType;
              String customerName = bill.customerName;
              if (customerName.isEmpty) {
                customerName = bill.customerCode.isNotEmpty ? bill.customerCode : 'Walk-in customer';
              }
              double lineTotal = bill.netPayable;
              if (lineTotal == 0) lineTotal = bill.grandTotal;
              if (isSaleReturn) lineTotal = -bill.subTotal.abs();

              return GestureDetector(
                onTap: () => _showBillPeek(context, bill),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(radiusLg),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isSaleReturn ? errBg.withValues(alpha: 0.5) : cs.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(radiusMd),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          isSaleReturn ? Icons.undo_rounded : Icons.receipt_long_rounded,
                          size: 18,
                          color: isSaleReturn ? err : cs.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${bill.invoiceNumber}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSaleReturn ? errBg.withValues(alpha: 0.45) : successBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isSaleReturn ? 'Sale Return' : 'Regular',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isSaleReturn ? err : success,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _formatMoney(lineTotal),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isSaleReturn ? err : cs.onSurface,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
