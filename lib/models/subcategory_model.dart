import 'dart:convert';

// Model for subcategory
class SubCategory {
  final String name;
  final String code;
  final String attributes;
  final String attributeTypes;
  final String? hsnCode;
  final String? unit;
  final String? description;
  final double? gstRate;
  bool isSelected;

  SubCategory(
      {required this.name,
      required this.code,
      required this.attributes,
      required this.attributeTypes,
      this.hsnCode,
      this.unit,
      this.description,
      this.isSelected = false,
      this.gstRate});

  static String _asJsonString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  factory SubCategory.fromJson(Map<String, dynamic> json) {
    return SubCategory(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      attributes: _asJsonString(json['attributes']),
      attributeTypes: _asJsonString(json['attribute_types']),
      hsnCode: json['hsn_code']?.toString(),
      unit: json['unit']?.toString() ?? 'Piece',
      description: json['description']?.toString() ?? '',
      gstRate: (json['gst_rate'] as num?)?.toDouble(),
    );
  }

  /// Builds from a `general_sub_categories` document.
  factory SubCategory.fromFirestoreData(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    final map = Map<String, dynamic>.from(data);
    if ((map['code'] == null || map['code'].toString().trim().isEmpty) &&
        documentId != null) {
      map['code'] = documentId;
    }
    return SubCategory.fromJson(map);
  }

  Map<String, dynamic> toFirestoreMap({
    required String genCatCode,
    required String createdAt,
    required String updatedAt,
    Map<String, dynamic>? remarks,
  }) {
    return {
      'code': code,
      'gen_cat_code': genCatCode,
      'name': name,
      'attributes': attributes,
      'attribute_types': attributeTypes,
      'hsn_code': hsnCode ?? '',
      'unit': unit ?? 'Piece',
      'description': description ?? '',
      'gst_rate': gstRate,
      'remarks': remarks ?? <String, dynamic>{},
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
