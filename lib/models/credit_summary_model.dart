import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentInfoModel {
  int? id;
  final bool isCredit;
  final bool isBillCompleted;
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
      'created_at': Timestamp.fromDate(createdAt),
      'customer_code': customerCode,
      'due_date': Timestamp.fromDate(dueDate),
    };
  }

  static fromMap(Map<String, dynamic> map) {
    return PaymentInfoModel(
      id: map['id'] ?? 0,
      isCredit: map['is_credit'] ?? false,
      isBillCompleted: true,
      paymentId: map['payment_id'] ?? '',
      remarks: map['remarks'] ?? '',
      totalAmount: (map['total_amount'] ?? 0).toDouble(),
      actualAmount: (map['actual_amount'] ?? 0).toDouble(),
      dueAmount: (map['due_amount'] ?? 0).toDouble(),
      createdAt: (map['created_at'] as Timestamp).toDate(),
      customerCode: map['customer_code'] ?? '',
      dueDate: (map['due_date'] as Timestamp).toDate(),
    );
  }
}
