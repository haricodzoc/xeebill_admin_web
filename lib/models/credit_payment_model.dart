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
      id: map['id'] as int?,
      active: map.containsKey('active') && map['active'] != null ? (map['active'] as int) == 1 : true,
      customerCode: map['customer_code']?.toString() ?? '',
      debitAmount: (map['debit_amount'] as num?)?.toDouble() ?? 0.0,
      dueAmount: (map['due_amount'] as num?)?.toDouble() ?? 0.0,
      settled: map['settled'] as int? ?? 0,
      remarks: map['remarks']?.toString() ?? '',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now(),
    );
  }
}
