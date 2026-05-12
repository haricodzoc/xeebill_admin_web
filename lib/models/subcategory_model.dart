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

  factory SubCategory.fromJson(Map<String, dynamic> json) {
    return SubCategory(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      attributes: json['attributes'] ?? '',
      attributeTypes: json['attribute_types'] ?? '',
      hsnCode: json['hsn_code'],
      unit: json['unit'] ?? 'Piece',
      description: json['description'] ?? '',
      gstRate: json['gst_rate']?.toDouble(),
    );
  }
}
