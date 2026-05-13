import 'package:flutter/material.dart';

import '../models/customer_info_model.dart';
import '../services/customer_credit_firestore_service.dart';
import '../utils/item_list_filters.dart';
import '../utils/functions.dart';
import 'customer_credit_balance_screen.dart';

/// Admin summary: receivables / payables with credit totals (Firestore `customers`).
class CreditPaymentsScreen extends StatefulWidget {
  final String userId;

  const CreditPaymentsScreen({super.key, required this.userId});

  @override
  State<CreditPaymentsScreen> createState() => _CreditPaymentsScreenState();
}

class _CreditPaymentsScreenState extends State<CreditPaymentsScreen> with SingleTickerProviderStateMixin {
  final _svc = CustomerCreditFirestoreService.instance;
  final _searchController = TextEditingController();

  late TabController _tabController;
  bool _isSearching = false;
  bool _loading = true;
  String? _error;
  String? _userDocumentId;
  List<CustomerInfoModel> _withCredit = [];
  final Set<String> _refreshingCodes = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = await _svc.resolveUserDocumentId(widget.userId);
      if (uid == null) {
        setState(() {
          _loading = false;
          _error = 'User document not found';
        });
        return;
      }
      final list = await _svc.loadCustomersWithCredit(uid);
      if (!mounted) return;
      setState(() {
        _userDocumentId = uid;
        _withCredit = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  String _norm(String s) => s.trim().toLowerCase();

  bool _matchesQuery(CustomerInfoModel c, String q) {
    if (q.isEmpty) return true;
    final n = _norm(q);
    return _norm(c.name).contains(n) ||
        _norm(c.phone).contains(n) ||
        _norm(c.code).contains(n);
  }

  List<CustomerInfoModel> _receivablesList() {
    final q = _isSearching ? _searchController.text : '';
    return _withCredit
        .where((c) => c.type == 'receivable' && _matchesQuery(c, q))
        .toList()
      ..sort((a, b) => naturalSortComparator(a.name, b.name));
  }

  List<CustomerInfoModel> _payablesList() {
    final q = _isSearching ? _searchController.text : '';
    return _withCredit
        .where((c) => c.type == 'payable' && _matchesQuery(c, q))
        .toList()
      ..sort((a, b) => naturalSortComparator(a.name, b.name));
  }

  Future<void> _refreshCustomerInList(CustomerInfoModel customer) async {
    final uid = _userDocumentId;
    if (uid == null) return;
    setState(() => _refreshingCodes.add(customer.code));
    try {
      final fresh = await _svc.fetchCustomer(uid, customer.code);
      if (!mounted) return;
      if (fresh != null) {
        final i = _withCredit.indexWhere((c) => c.code == customer.code);
        if (i >= 0) {
          setState(() => _withCredit[i] = fresh);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _refreshingCodes.remove(customer.code));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search customers…',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: cs.onSurfaceVariant),
                ),
                onChanged: (_) => setState(() {}),
              )
            : const Text('Credits & Payments'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Receivables'),
            Tab(text: 'Payables'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                }
              });
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'refresh') {
                await _load();
                if (mounted) {
                  showSnackbar(context, 'Refreshed');
                }
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'refresh', child: Text('Refresh')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!, textAlign: TextAlign.center))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_receivablesList(), emptyTitle: 'No receivables found', emptyHint: 'Receivables with opening or bill credit appear here.'),
                _buildList(_payablesList(), emptyTitle: 'No payables found', emptyHint: 'Payable suppliers with credit appear here.'),
              ],
            ),
    );
  }

  Widget _buildList(List<CustomerInfoModel> list, {required String emptyTitle, required String emptyHint}) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(emptyTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                _isSearching && _searchController.text.isNotEmpty
                    ? 'No matches for "${_searchController.text}"'
                    : emptyHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final customer = list[index];
        return _CustomerCreditCard(
          customer: customer,
          userDocumentId: _userDocumentId!,
          isRefreshing: _refreshingCodes.contains(customer.code),
          onOpenBalance: () async {
            final uid = _userDocumentId;
            if (uid == null) return;
            final updated = await Navigator.push<CustomerInfoModel>(
              context,
              MaterialPageRoute(
                builder: (ctx) => CustomerCreditBalanceScreen(
                  userDocumentId: uid,
                  customer: customer,
                ),
              ),
            );
            if (updated != null && mounted) {
              final i = _withCredit.indexWhere((c) => c.code == updated.code);
              if (i >= 0) {
                setState(() => _withCredit[i] = updated);
              }
            }
          },
          onRefreshCredit: () async {
            await _refreshCustomerInList(customer);
            if (mounted) {
              showSnackbar(context, 'Customer refreshed from server');
            }
          },
        );
      },
    );
  }
}

class _CustomerCreditCard extends StatelessWidget {
  final CustomerInfoModel customer;
  final String userDocumentId;
  final bool isRefreshing;
  final VoidCallback onOpenBalance;
  final VoidCallback onRefreshCredit;

  const _CustomerCreditCard({
    required this.customer,
    required this.userDocumentId,
    required this.isRefreshing,
    required this.onOpenBalance,
    required this.onRefreshCredit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showCreditBox = customer.totalCredit > 0 || customer.totalDebit > 0 || customer.totalDue > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_rounded, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  customer.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  customer.code,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
          if (customer.phone.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.phone_rounded, color: cs.onSurfaceVariant, size: 16),
                const SizedBox(width: 8),
                Text(customer.phone, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ],
          if (customer.address.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_rounded, color: cs.onSurfaceVariant, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      customer.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          if (customer.gstNo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_rounded, color: cs.onSurfaceVariant, size: 16),
                  const SizedBox(width: 8),
                  Text('GST: ${customer.gstNo}', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          if (showCreditBox)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: customer.totalDue > 0 ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: customer.totalDue > 0 ? Colors.red.shade200 : Colors.green.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.credit_card_rounded,
                          color: customer.totalDue > 0 ? Colors.red.shade700 : Colors.green.shade700,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Credit information',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: customer.totalDue > 0 ? Colors.red.shade700 : Colors.green.shade700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _kv(context, 'Total credit:', '₹${customer.totalCredit.toStringAsFixed(2)}', Colors.grey.shade800),
                    const SizedBox(height: 4),
                    _kv(context, 'Total settled:', '₹${customer.totalDebit.toStringAsFixed(2)}', Colors.green.shade700),
                    const SizedBox(height: 8),
                    Divider(height: 1, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Due amount:',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: customer.totalDue > 0 ? Colors.red.shade700 : Colors.green.shade700,
                              ),
                        ),
                        Text(
                          '₹${customer.totalDue.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: customer.totalDue > 0 ? Colors.red.shade700 : Colors.green.shade700,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (customer.remarks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.note_rounded, color: cs.onSurfaceVariant, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        customer.remarks,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Divider(height: 1, color: Colors.grey.shade300),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                InkWell(
                  onTap: onOpenBalance,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.28)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet_rounded, color: cs.primary, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'View balance sheet',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded, color: cs.primary, size: 12),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                isRefreshing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: 'Reload customer from Firestore',
                        icon: Icon(Icons.refresh_rounded, color: cs.primary, size: 22),
                        onPressed: onRefreshCredit,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, Color vColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700)),
        Text(
          v,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: vColor),
        ),
      ],
    );
  }
}
