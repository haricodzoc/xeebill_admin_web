class CustomerInfoModel {
  int? id;
  String code;
  String name;
  String address;
  String gstNo;
  String phone;
  String remarks;
  DateTime? dueDate;
  double totalCredit = 0;
  double totalDebit = 0;
  double totalDue = 0;
  int totalVisits = 0;
  final DateTime createdAt;
  DateTime updatedAt;

  CustomerInfoModel({
    this.id,
    required this.code,
    required this.name,
    required this.address,
    required this.gstNo,
    required this.phone,
    required this.remarks,
    required this.totalCredit,
    required this.totalDebit,
    required this.totalDue,
    required this.totalVisits,
    this.dueDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'code': code,
      'name': name,
      'address': address,
      'gst_no': gstNo,
      'phone': phone,
      'remarks': remarks,
      'total_credit': totalCredit,
      'total_debit': totalDebit,
      'total_due': totalDue,
      'total_visits': totalVisits,
      'due_date': dueDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    return map;
  }

  factory CustomerInfoModel.fromMap(Map<String, dynamic> map) {
    final customer = CustomerInfoModel(
      id: map['id'] as int?,
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      gstNo: map['gst_no']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      remarks: map['remarks']?.toString() ?? '',
      totalVisits: (map['total_visits'] as int?) ?? 0,
      totalCredit: (map['total_credit'] as num?)?.toDouble() ?? 0.0,
      totalDebit: (map['total_debit'] as num?)?.toDouble() ?? 0.0,
      totalDue: (map['total_due'] as num?)?.toDouble() ?? 0.0,
      dueDate:
          map.containsKey('due_date') && map['due_date'] != null && map['due_date'] != '' && map['due_date'] != 'null'
              ? DateTime.parse(map['due_date'] as String)
              : DateTime.now(),
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now(),
    );

    return customer;
  }
}
