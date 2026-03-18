import 'package:cloud_firestore/cloud_firestore.dart';

class CategoryModel {
  int? id;
  String code;
  String parentCode;
  String attributes;
  String attributeTypes;
  bool active;
  String name;
  String unit;
  String hsnCode;
  double taxPercentage;
  DateTime createdAt;
  DateTime updatedAt;

  CategoryModel({
    this.id,
    required this.code,
    required this.parentCode,
    required this.name,
    required this.attributes,
    required this.attributeTypes,
    required this.active,
    required this.unit,
    required this.hsnCode,
    required this.taxPercentage,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap({bool isRestoring = false}) {
    final map = {
      'id': id,
      'code': code,
      'parent_code': parentCode,
      'active': active ? 1 : 0,
      'name': name,
      'attributes': attributes,
      'attribute_types': attributeTypes,
      'unit': unit,
      'hsn_code': hsnCode,
      'tax_percentage': taxPercentage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    return map;
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
      hsnCode: map['hsn_code']?.toString() ?? '',
      taxPercentage: (map['tax_percentage'] as num?)?.toDouble() ?? 0.0,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now(),
      attributeTypes: map.containsKey('attribute_types') ? map['attribute_types']?.toString() ?? '' : '',
      attributes: map.containsKey('attributes') ? map['attributes']?.toString() ?? '' : '',
      parentCode: map.containsKey('parent_code') ? map['parent_code']?.toString() ?? '' : '',
      active: map.containsKey('active') && map['active'] != null
          ? (map['active'] as int) == 1
          : true, // Default to true if not present
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now(),
    );
  }

  factory CategoryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Helper to parse timestamp
    DateTime? _parseTimestamp(dynamic timestamp) {
      if (timestamp == null) return null;
      if (timestamp is Timestamp) {
        return timestamp.toDate();
      } else if (timestamp is String) {
        try {
          return DateTime.parse(timestamp);
        } catch (e) {
          return null;
        }
      } else if (timestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    }

    return CategoryModel(
      id: data['id'] as int?,
      code: data['code']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      unit: data['unit']?.toString() ?? '',
      hsnCode: data['hsn_code']?.toString() ?? '',
      taxPercentage: (data['tax_percentage'] as num?)?.toDouble() ?? 0.0,
      attributes: data['attributes']?.toString() ?? '',
      attributeTypes: data['attribute_types']?.toString() ?? '',
      parentCode: data['parent_code']?.toString() ?? '',
      active: data['active'] != false && data['active'] != 0,
      createdAt: _parseTimestamp(data['created_at']) ?? DateTime.now(),
      updatedAt: _parseTimestamp(data['updated_at']) ?? DateTime.now(),
    );
  }
}
