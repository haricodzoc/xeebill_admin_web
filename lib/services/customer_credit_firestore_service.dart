import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/bill_model.dart';
import '../models/credit_payment_model.dart';
import '../models/credit_summary_model.dart';
import '../models/customer_info_model.dart';

DateTime _parseDyn(dynamic v, [DateTime? fallback]) {
  if (v == null) return fallback ?? DateTime.now();
  if (v is Timestamp) return v.toDate();
  if (v is String) {
    final d = DateTime.tryParse(v);
    if (d != null) return d;
  }
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  return fallback ?? DateTime.now();
}

double _readNum(Map<String, dynamic> data, List<String> keys) {
  for (final k in keys) {
    final v = data[k];
    if (v is num) return v.toDouble();
    if (v is String) {
      final p = double.tryParse(v.trim());
      if (p != null) return p;
    }
  }
  return 0.0;
}

/// Firestore-backed credits / payments for admin web (`users/{userDocId}/...`).
class CustomerCreditFirestoreService {
  CustomerCreditFirestoreService._();
  static final instance = CustomerCreditFirestoreService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  Future<String?> resolveUserDocumentId(String userId) async {
    final q = await _fs.collection('users').where('userId', isEqualTo: userId).limit(1).get();
    if (q.docs.isNotEmpty) return q.docs.first.id;
    final d = await _fs.collection('users').doc(userId).get();
    if (d.exists) return userId;
    return null;
  }

  Future<List<CustomerInfoModel>> loadCustomersWithCredit(String userDocId) async {
    final byCode = <String, CustomerInfoModel>{};

    Future<void> ingestCollection(String collectionName) async {
      final snap = await _fs.collection('users').doc(userDocId).collection(collectionName).get();
      for (final d in snap.docs) {
        try {
          final raw = d.data();
          final data = Map<String, dynamic>.from(raw);
          if ((data['code'] ?? '').toString().trim().isEmpty) {
            data['code'] = d.id;
          }
          final c = CustomerInfoModel.fromMap(data);
          // Match mobile intent: list credit-related customers; Firestore may use camelCase totals
          // or only keep `total_due` in sync while `total_credit` is 0.
          final hasActivity =
              c.totalCredit > 0.0001 || c.totalDue > 0.0001 || c.totalDebit > 0.0001;
          if (!hasActivity) continue;
          final prev = byCode[c.code];
          if (prev == null || c.updatedAt.isAfter(prev.updatedAt)) {
            byCode[c.code] = c;
          }
        } catch (e) {
          debugPrint('Skip customer ${d.id} in $collectionName: $e');
        }
      }
    }

    // Mobile backs up to `customer_info`; admin bills screen uses `customers`.
    await ingestCollection('customers');
    await ingestCollection('customer_info');

    final out = byCode.values.toList();
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<DocumentReference<Map<String, dynamic>>> _customerRef(String userDocId, String code) async {
    for (final coll in const ['customers', 'customer_info']) {
      final byId = _fs.collection('users').doc(userDocId).collection(coll).doc(code);
      final s1 = await byId.get();
      if (s1.exists) return byId;
      final q = await _fs
          .collection('users')
          .doc(userDocId)
          .collection(coll)
          .where('code', isEqualTo: code)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.reference;
    }
    throw StateError('Customer document not found for code: $code');
  }

  Future<CustomerInfoModel?> fetchCustomer(String userDocId, String customerCode) async {
    try {
      final ref = await _customerRef(userDocId, customerCode);
      final doc = await ref.get();
      if (!doc.exists) return null;
      final data = Map<String, dynamic>.from(doc.data() ?? {});
      if ((data['code'] ?? '').toString().trim().isEmpty) {
        data['code'] = doc.id;
      }
      return CustomerInfoModel.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Bills (credit), direct_credit docs, and credit_payments (debits), sorted with running balance.
  Future<List<PaymentInfoModel>> loadBalanceSheet(String userDocId, CustomerInfoModel c) async {
    final rows = <PaymentInfoModel>[];

    try {
      final billsSnap = await _fs
          .collection('users')
          .doc(userDocId)
          .collection('bills')
          .where('customer_code', isEqualTo: c.code)
          .limit(500)
          .get();
      for (final d in billsSnap.docs) {
        try {
          final bill = BillModel.fromFirestore(d);
          if (bill.creditAmount <= 0) continue;
          rows.add(
            PaymentInfoModel(
              id: bill.id,
              dueDate: bill.dueDate,
              isCredit: true,
              isBillCompleted: bill.completed,
              settled: 0,
              customerCode: bill.customerCode,
              remarks: bill.billCode.startsWith('DIRECT_CREDIT_') ? bill.additionalInfo.toString() : '',
              paymentId: 'BILL-${bill.invoiceNumber}',
              totalAmount: bill.creditAmount,
              actualAmount: bill.creditAmount,
              dueAmount: 0,
              createdAt: bill.billDate,
            ),
          );
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('loadBalanceSheet bills: $e');
    }

    try {
      final dcSnap = await _fs
          .collection('users')
          .doc(userDocId)
          .collection('direct_credit')
          .where('customer_code', isEqualTo: c.code)
          .limit(200)
          .get();
      for (final d in dcSnap.docs) {
        final m = d.data();
        final amt = (m['credit_amount'] as num?)?.toDouble() ?? 0.0;
        if (amt <= 0) continue;
        rows.add(
          PaymentInfoModel(
            dueDate: _parseDyn(m['due_date'] ?? m['dueDate']),
            isCredit: true,
            isBillCompleted: true,
            settled: 0,
            customerCode: c.code,
            remarks: m['remarks']?.toString() ?? 'Direct credit',
            paymentId: 'DIRECT-${d.id}',
            totalAmount: amt,
            actualAmount: amt,
            dueAmount: 0,
            createdAt: _parseDyn(m['created_at'] ?? m['createdAt']),
          ),
        );
      }
    } catch (e) {
      debugPrint('loadBalanceSheet direct_credit: $e');
    }

    try {
      // Mobile backup: `credit_payment` (singular). Older web builds may use `credit_payments`.
      final seenPaths = <String>{};
      var idx = 1;
      for (final coll in const ['credit_payment', 'credit_payments']) {
        final paySnap = await _fs
            .collection('users')
            .doc(userDocId)
            .collection(coll)
            .where('customer_code', isEqualTo: c.code)
            .limit(500)
            .get();
        for (final d in paySnap.docs) {
          if (!seenPaths.add(d.reference.path)) continue;
          try {
            final m = Map<String, dynamic>.from(d.data());
            final p = CreditPaymentModel.fromFirestoreMap(m);
            if (p.debitAmount <= 0) continue;
            rows.add(
              PaymentInfoModel(
                id: p.id,
                dueDate: p.createdAt,
                isCredit: false,
                isBillCompleted: true,
                settled: p.settled,
                customerCode: p.customerCode,
                remarks: p.remarks,
                paymentId: 'PAYMENT ${idx++}',
                totalAmount: p.debitAmount,
                actualAmount: p.debitAmount,
                dueAmount: 0,
                createdAt: p.createdAt,
              ),
            );
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('loadBalanceSheet credit_payment(s): $e');
    }

    rows.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    var running = 0.0;
    final withBalance = <PaymentInfoModel>[];
    for (final e in rows) {
      if (e.isCredit) {
        running += e.totalAmount;
      } else {
        running -= e.totalAmount;
      }
      withBalance.add(
        PaymentInfoModel(
          id: e.id,
          dueDate: e.dueDate,
          isCredit: e.isCredit,
          isBillCompleted: e.isBillCompleted,
          settled: e.settled,
          customerCode: e.customerCode,
          remarks: e.remarks,
          paymentId: e.paymentId,
          totalAmount: e.totalAmount,
          actualAmount: e.actualAmount,
          dueAmount: running,
          createdAt: e.createdAt,
        ),
      );
    }
    return withBalance;
  }

  Future<int> addDebitPayment({
    required String userDocId,
    required CustomerInfoModel customer,
    required double amount,
    required String remarks,
  }) async {
    if (amount <= 0) return -1;
    final custRef = await _customerRef(userDocId, customer.code);
    final payRef = _fs.collection('users').doc(userDocId).collection('credit_payment').doc();

    await _fs.runTransaction((txn) async {
      final snap = await txn.get(custRef);
      if (!snap.exists) {
        throw StateError('Customer not found');
      }
      final data = snap.data() ?? {};
      final due = _readNum(data, ['total_due', 'totalDue']);
      final debit = _readNum(data, ['total_debit', 'totalDebit']);
      final newDue = due - amount;
      final settled = newDue <= 0.0001 ? 1 : 0;
      txn.set(payRef, {
        'customer_code': customer.code,
        'debit_amount': amount,
        'due_amount': newDue < 0 ? 0.0 : newDue,
        'settled': settled,
        'remarks': remarks,
        'active': 1,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      final newDebit = debit + amount;
      final clampedDue = newDue < 0 ? 0.0 : newDue;
      txn.update(custRef, {
        'total_debit': newDebit,
        'total_due': clampedDue,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
    return 1;
  }

  Future<int> addDirectCredit({
    required String userDocId,
    required CustomerInfoModel customer,
    required double amount,
    required String remarks,
    required DateTime dueDate,
  }) async {
    if (amount <= 0) return -1;
    final custRef = await _customerRef(userDocId, customer.code);
    final dcRef = _fs.collection('users').doc(userDocId).collection('direct_credit').doc();

    await _fs.runTransaction((txn) async {
      final snap = await txn.get(custRef);
      if (!snap.exists) {
        throw StateError('Customer not found');
      }
      final data = snap.data() ?? {};
      final credit = _readNum(data, ['total_credit', 'totalCredit']);
      final due = _readNum(data, ['total_due', 'totalDue']);
      final newCredit = credit + amount;
      final newDue = due + amount;
      txn.set(dcRef, {
        'customer_code': customer.code,
        'credit_amount': amount,
        'remarks': remarks,
        'due_date': Timestamp.fromDate(dueDate),
        'created_at': FieldValue.serverTimestamp(),
      });
      txn.update(custRef, {
        'total_credit': newCredit,
        'total_due': newDue,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
    return 1;
  }
}