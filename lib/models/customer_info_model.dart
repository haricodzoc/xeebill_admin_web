import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerInfoModel {
  int? id;
  String code;
  String name;
  String address;
  String gstNo;
  String phone;
  String remarks;
  /// `receivable` (customers owe you) or `payable` (you owe them), aligned with mobile `customer_info`.
  String type;
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
    this.type = 'receivable',
    required this.totalCredit,
    required this.totalDebit,
    required this.totalDue,
    required this.totalVisits,
    this.dueDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  CustomerInfoModel copyWith({
    double? totalCredit,
    double? totalDebit,
    double? totalDue,
    DateTime? updatedAt,
  }) {
    return CustomerInfoModel(
      id: id,
      code: code,
      name: name,
      address: address,
      gstNo: gstNo,
      phone: phone,
      remarks: remarks,
      type: type,
      totalCredit: totalCredit ?? this.totalCredit,
      totalDebit: totalDebit ?? this.totalDebit,
      totalDue: totalDue ?? this.totalDue,
      totalVisits: totalVisits,
      dueDate: dueDate,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    final map = {
      'id': id,
      'code': code,
      'name': name,
      'address': address,
      'gst_no': gstNo,
      'phone': phone,
      'remarks': remarks,
      'type': type,
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

  static String _normalizeType(dynamic raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    if (s.contains('payable')) return 'payable';
    // Mobile uses `receivable`, `customer_with_bill`, etc. — all non-payables go to Receivables tab.
    return 'receivable';
  }

  static double _readDouble(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v is num) return v.toDouble();
      if (v is String) {
        final p = double.tryParse(v.trim());
        if (p != null) return p;
      }
    }
    return 0.0;
  }

  static int _readInt(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? 0;
    }
    return 0;
  }

  static DateTime? _parseOptionalDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null') return null;
    return DateTime.tryParse(s);
  }

  static DateTime _parseDate(dynamic v, DateTime fallback) {
    return _parseOptionalDate(v) ?? fallback;
  }

  factory CustomerInfoModel.fromMap(Map<String, dynamic> map) {
    return CustomerInfoModel(
      id: map['id'] is int ? map['id'] as int? : int.tryParse(map['id']?.toString() ?? ''),
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      gstNo: (map['gst_no'] ?? map['gstNo'])?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      remarks: map['remarks']?.toString() ?? '',
      type: _normalizeType(map['type'] ?? map['customer_type'] ?? map['customerType']),
      totalVisits: _readInt(map, ['total_visits', 'totalVisits']),
      totalCredit: _readDouble(map, ['total_credit', 'totalCredit']),
      totalDebit: _readDouble(map, ['total_debit', 'totalDebit']),
      totalDue: _readDouble(map, ['total_due', 'totalDue']),
      dueDate: _parseOptionalDate(map['due_date'] ?? map['dueDate']),
      createdAt: _parseDate(map['created_at'] ?? map['createdAt'], DateTime.now()),
      updatedAt: _parseDate(map['updated_at'] ?? map['updatedAt'], DateTime.now()),
    );
  }
}
