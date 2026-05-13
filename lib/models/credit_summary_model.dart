import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentInfoModel {
  int? id;
  final bool isCredit;
  final bool isBillCompleted;
  final int settled;
  final String customerCode;
  final String remarks;
  final String paymentId;
  final double totalAmount;
  final double actualAmount;
  final double dueAmount;
  final DateTime dueDate;
  final DateTime createdAt;

  PaymentInfoModel({
    this.id,
    required this.dueDate,
    required this.isCredit,
    required this.isBillCompleted,
    this.settled = 0,
    required this.customerCode,
    required this.remarks,
    required this.paymentId,
    required this.totalAmount,
    required this.actualAmount,
    required this.dueAmount,
    required this.createdAt,
  });

  Map<String, dynamic> toMap({bool isRestoring = false}) {
    return {
      'id': id,
      'is_credit': isCredit,
      'payment_id': paymentId,
      'total_amount': totalAmount,
      'remarks': remarks,
      'actual_amount': actualAmount,
      'due_amount': dueAmount,
      'settled': settled,
      'created_at': Timestamp.fromDate(createdAt),
      'customer_code': customerCode,
      'due_date': Timestamp.fromDate(dueDate),
    };
  }

  static DateTime _parseDate(dynamic v, DateTime fallback) {
    if (v == null) return fallback;
    if (v is Timestamp) return v.toDate();
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return d;
    }
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return fallback;
  }

  factory PaymentInfoModel.fromMap(Map<String, dynamic> map) {
    return PaymentInfoModel(
      id: map['id'] is int ? map['id'] as int? : int.tryParse(map['id']?.toString() ?? ''),
      isCredit: map['is_credit'] == true || map['is_credit'] == 1,
      isBillCompleted: true,
      settled: (map['settled'] as num?)?.toInt() ?? 0,
      paymentId: map['payment_id']?.toString() ?? '',
      remarks: map['remarks']?.toString() ?? '',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      actualAmount: (map['actual_amount'] as num?)?.toDouble() ?? 0.0,
      dueAmount: (map['due_amount'] as num?)?.toDouble() ?? 0.0,
      createdAt: _parseDate(map['created_at'], DateTime.now()),
      customerCode: map['customer_code']?.toString() ?? '',
      dueDate: _parseDate(map['due_date'], DateTime.now()),
    );
  }
}
