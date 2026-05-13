import 'package:cloud_firestore/cloud_firestore.dart';

class CreditPaymentModel {
  int? id;
  String customerCode;
  final double debitAmount;
  final double dueAmount;
  final String remarks;
  final int settled;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  CreditPaymentModel({
    this.id,
    required this.customerCode,
    required this.debitAmount,
    required this.dueAmount,
    required this.remarks,
    required this.settled,
    required this.active,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'active': active ? 1 : 0,
      'customer_code': customerCode,
      'debit_amount': debitAmount,
      'due_amount': dueAmount,
      'settled': settled,
      'remarks': remarks,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    return map;
  }

  factory CreditPaymentModel.fromMap(Map<String, dynamic> map) {
    return CreditPaymentModel(
      id: map['id'] is int ? map['id'] as int? : int.tryParse(map['id']?.toString() ?? ''),
      active: _parseActive(map['active']),
      customerCode: map['customer_code']?.toString() ?? '',
      debitAmount: (map['debit_amount'] as num?)?.toDouble() ?? 0.0,
      dueAmount: (map['due_amount'] as num?)?.toDouble() ?? 0.0,
      settled: (map['settled'] as num?)?.toInt() ?? 0,
      remarks: map['remarks']?.toString() ?? '',
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now(),
    );
  }

  static bool _parseActive(dynamic v) {
    if (v == null) return true;
    if (v is bool) return v;
    return v == 1;
  }

  static DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  factory CreditPaymentModel.fromFirestoreMap(Map<String, dynamic> map) {
    return CreditPaymentModel.fromMap(map);
  }
}
