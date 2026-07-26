import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user_model.dart';

class UserPaymentHistoryScreen extends StatefulWidget {
  final UserModel user;

  const UserPaymentHistoryScreen({
    super.key,
    required this.user,
  });

  @override
  State<UserPaymentHistoryScreen> createState() =>
      _UserPaymentHistoryScreenState();
}

class _UserPaymentHistoryScreenState extends State<UserPaymentHistoryScreen> {
  static const int _pageSize = 20;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;
  DocumentReference<Map<String, dynamic>>? _userRef;

  String _accountStatusText = '';
  String _expiryText = 'Not set';
  bool _isAccountActive = true;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _payments = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastPaymentDoc;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolveUserDocRef(
    UserModel user,
  ) async {
    final listedDocId = user.docId?.trim();
    if (listedDocId != null && listedDocId.isNotEmpty) {
      final ref = _firestore.collection('users').doc(listedDocId);
      final snap = await ref.get();
      if (snap.exists) return ref;
    }

    final uid = user.userId?.trim();
    if (uid != null && uid.isNotEmpty) {
      final byId = _firestore.collection('users').doc(uid);
      final snap = await byId.get();
      if (snap.exists) return byId;

      final q = await _firestore
          .collection('users')
          .where('userId', isEqualTo: uid)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.reference;
    }

    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      final q = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.reference;
    }

    return null;
  }

  DateTime? _parseCreatedAt(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  DateTime? _parseExpiry(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  Future<String> _planTitleForId(String? planId) async {
    final id = planId?.trim();
    if (id == null || id.isEmpty) return 'Free';
    try {
      final snap = await _firestore.collection('recharge_plans').get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final pid = (data['plan_id'] ?? '').toString().trim();
        if (pid == id) {
          final title = (data['title'] ?? '').toString().trim();
          return title.isEmpty ? id : title;
        }
      }
    } catch (_) {}
    return 'Unknown Plan ($id)';
  }

  Future<void> _loadUserSummary(DocumentReference<Map<String, dynamic>> ref) async {
    final snap = await ref.get();
    final data = snap.data();
    if (data == null) return;

    final expiry = _parseExpiry(data['accountExpiry']);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (expiry != null) {
      final expiryDate = DateTime(expiry.year, expiry.month, expiry.day);
      _expiryText = DateFormat('dd MMM yyyy').format(expiryDate);
      _isAccountActive =
          !expiryDate.isBefore(today);
    } else {
      _expiryText = 'Not set';
      _isAccountActive = true;
    }

    final planTitle = await _planTitleForId(data['planId']?.toString());
    if (_isAccountActive) {
      _accountStatusText = planTitle == 'Free'
          ? 'Free plan'
          : 'Active Plan: $planTitle';
    } else {
      _accountStatusText =
          'Account expired. Last plan: $planTitle';
    }
  }

  Future<void> _fetchPaymentsPage({bool reset = false}) async {
    final ref = _userRef;
    if (ref == null) return;

    if (reset) {
      _lastPaymentDoc = null;
      _hasMore = true;
      _payments.clear();
    }

    if (!_hasMore) return;

    Query<Map<String, dynamic>> query = ref
        .collection('payments')
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    if (_lastPaymentDoc != null) {
      query = query.startAfterDocument(_lastPaymentDoc!);
    }

    final snap = await query.get();
    if (snap.docs.isEmpty) {
      _hasMore = false;
      return;
    }

    _payments.addAll(snap.docs);
    _lastPaymentDoc = snap.docs.last;
    if (snap.docs.length < _pageSize) {
      _hasMore = false;
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ref = await _resolveUserDocRef(widget.user);
      if (ref == null) {
        setState(() {
          _errorMessage = 'Unable to find this user document';
          _isLoading = false;
        });
        return;
      }

      _userRef = ref;
      await _loadUserSummary(ref);
      await _fetchPaymentsPage(reset: true);

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading payment history: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      await _fetchPaymentsPage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading more: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  ({double amount, String status, String paymentId, String createdText})
      _parsePayment(Map<String, dynamic> data) {
    final rawAmount = data['amount'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse('$rawAmount') ?? 0.0;
    final status = (data['status'] ?? '').toString();
    final paymentId = (data['paymentId'] ?? '').toString();
    final createdAt = _parseCreatedAt(data['createdAt']);
    final createdText = createdAt != null
        ? DateFormat('dd-MM-yyyy HH:mm').format(createdAt)
        : '—';
    return (
      amount: amount,
      status: status,
      paymentId: paymentId,
      createdText: createdText,
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'success':
        return Colors.green;
      case 'failure':
        return Colors.red;
      case 'external_wallet':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'success':
        return Icons.check_circle_rounded;
      case 'failure':
        return Icons.error_rounded;
      case 'external_wallet':
        return Icons.account_balance_wallet_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  void _showPaymentDetails(Map<String, dynamic> data) {
    final parsed = _parsePayment(data);
    final orderId = (data['orderId'] ?? '').toString();
    final message = (data['message'] ?? '').toString();
    final isSubscription = data['isSubscription'] == true;
    final duration = data['durationInDays'];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Amount: ₹${parsed.amount.toStringAsFixed(2)}'),
              Text('Status: ${parsed.status}'),
              Text(
                'Payment ID: ${parsed.paymentId.isNotEmpty ? parsed.paymentId : '—'}',
              ),
              Text('Order ID: ${orderId.isNotEmpty ? orderId : '—'}'),
              Text('Created: ${parsed.createdText}'),
              if (message.isNotEmpty) Text('Message: $message'),
              Text('Subscription: ${isSubscription ? 'Yes' : 'No'}'),
              if (duration != null) Text('Duration (days): $duration'),
            ],
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

  Widget _buildStatusCard() {
    final statusColor = _isAccountActive ? Colors.green : Colors.red;
    final statusIcon =
        _isAccountActive ? Icons.verified_rounded : Icons.cancel_rounded;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.12),
                  child: Icon(statusIcon, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Account Status',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isAccountActive ? 'Active' : 'Expired',
                        style: TextStyle(color: statusColor, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_accountStatusText, style: TextStyle(color: Colors.grey[700])),
            const SizedBox(height: 6),
            Text('Expires: $_expiryText', style: TextStyle(color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userName = (widget.user.name ?? 'User').trim();

    return Scaffold(
      appBar: AppBar(
        title: Text('Payment History • $userName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadInitial,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadInitial,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStatusCard(),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'Payment History',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadInitial,
                        child: _payments.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 80),
                                  Center(child: Text('No payments found')),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  16,
                                ),
                                itemCount:
                                    _payments.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= _payments.length) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Center(
                                        child: _isLoadingMore
                                            ? const CircularProgressIndicator()
                                            : TextButton(
                                                onPressed: _loadMore,
                                                child: const Text('Load more'),
                                              ),
                                      ),
                                    );
                                  }

                                  final doc = _payments[index];
                                  final data = doc.data();
                                  final parsed = _parsePayment(data);
                                  final statusColor =
                                      _statusColor(parsed.status);

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor:
                                            statusColor.withValues(alpha: 0.12),
                                        child: const Icon(
                                          Icons.receipt_long_rounded,
                                          color: Colors.teal,
                                        ),
                                      ),
                                      title: Text(
                                        '₹${parsed.amount.toStringAsFixed(parsed.amount.truncateToDouble() == parsed.amount ? 0 : 2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                            parsed.paymentId.isNotEmpty
                                                ? 'ID: ${parsed.paymentId}'
                                                : 'ID: —',
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'On: ${parsed.createdText}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                      trailing: Icon(
                                        _statusIcon(parsed.status),
                                        color: statusColor,
                                      ),
                                      onTap: () => _showPaymentDetails(data),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
