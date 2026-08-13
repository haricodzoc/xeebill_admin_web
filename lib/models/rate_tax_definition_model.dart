import 'package:cloud_firestore/cloud_firestore.dart';

enum RateCompareOp { lt, lte, gt, gte, eq }

extension RateCompareOpX on RateCompareOp {
  String get firestoreValue {
    switch (this) {
      case RateCompareOp.lt:
        return 'lt';
      case RateCompareOp.lte:
        return 'lte';
      case RateCompareOp.gt:
        return 'gt';
      case RateCompareOp.gte:
        return 'gte';
      case RateCompareOp.eq:
        return 'eq';
    }
  }

  String get symbol {
    switch (this) {
      case RateCompareOp.lt:
        return '<';
      case RateCompareOp.lte:
        return '≤';
      case RateCompareOp.gt:
        return '>';
      case RateCompareOp.gte:
        return '≥';
      case RateCompareOp.eq:
        return '=';
    }
  }

  String get label {
    switch (this) {
      case RateCompareOp.lt:
        return 'Less than';
      case RateCompareOp.lte:
        return 'Less than or equal';
      case RateCompareOp.gt:
        return 'Greater than';
      case RateCompareOp.gte:
        return 'Greater than or equal';
      case RateCompareOp.eq:
        return 'Equal to';
    }
  }

  static RateCompareOp fromValue(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'lt':
      case '<':
        return RateCompareOp.lt;
      case 'lte':
      case '<=':
      case '≤':
        return RateCompareOp.lte;
      case 'gt':
      case '>':
        return RateCompareOp.gt;
      case 'gte':
      case '>=':
      case '≥':
        return RateCompareOp.gte;
      case 'eq':
      case '=':
        return RateCompareOp.eq;
      default:
        return RateCompareOp.lt;
    }
  }
}

class RateTaxSlab {
  final RateCompareOp operator;
  final double amount;
  final double taxPerc;

  const RateTaxSlab({
    required this.operator,
    required this.amount,
    required this.taxPerc,
  });

  String get preview =>
      'Rate ${operator.symbol} ₹${_fmt(amount)}  →  ${taxPerc.toStringAsFixed(taxPerc == taxPerc.roundToDouble() ? 0 : 2)}%';

  Map<String, dynamic> toMap() {
    return {
      'operator': operator.firestoreValue,
      'amount': amount,
      'tax_perc': taxPerc,
    };
  }

  factory RateTaxSlab.fromMap(Map<String, dynamic> map) {
    return RateTaxSlab(
      operator: RateCompareOpX.fromValue(map['operator']?.toString()),
      amount: _toDouble(map['amount']),
      taxPerc: _toDouble(map['tax_perc'] ?? map['taxPerc'] ?? map['tax']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) {
      return v.toStringAsFixed(0);
    }
    return v.toStringAsFixed(2);
  }
}

class RateTaxDefinition {
  final String id;
  final String parentCategoryCode;
  final String parentCategoryName;
  final List<RateTaxSlab> slabs;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RateTaxDefinition({
    required this.id,
    required this.parentCategoryCode,
    required this.parentCategoryName,
    required this.slabs,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'parent_category_code': parentCategoryCode,
      'parent_category_name': parentCategoryName,
      'slabs': slabs.map((s) => s.toMap()).toList(),
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  factory RateTaxDefinition.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final rawSlabs = data['slabs'];
    final slabs = <RateTaxSlab>[];
    if (rawSlabs is List) {
      for (final item in rawSlabs) {
        if (item is Map) {
          slabs.add(RateTaxSlab.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }
    return RateTaxDefinition(
      id: doc.id,
      parentCategoryCode: (data['parent_category_code'] ?? '').toString(),
      parentCategoryName: (data['parent_category_name'] ?? '').toString(),
      slabs: slabs,
      createdAt: _parseDate(data['created_at']),
      updatedAt: _parseDate(data['updated_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
