class ServiceOrderItemModel {
  int? id;
  int serviceId;
  String code;
  String name;
  String unit;
  String hsnCode;
  String categoryCode;
  double price;
  double quantity;
  double total;
  double taxPerc;
  double totalAfterTax;
  bool isReturned;

  ServiceOrderItemModel({
    this.id,
    this.serviceId = 0,
    required this.name,
    required this.hsnCode,
    required this.unit,
    required this.categoryCode,
    required this.code,
    required this.price,
    required this.quantity,
    required this.total,
    required this.taxPerc,
    required this.totalAfterTax,
    this.isReturned = false,
  });

  factory ServiceOrderItemModel.fromMap(Map<String, dynamic> map) {
    return ServiceOrderItemModel(
      id: map['id'] is int ? map['id'] as int? : int.tryParse(map['id']?.toString() ?? ''),
      serviceId: (map['service_id'] as num?)?.toInt() ?? 0,
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
      hsnCode: (map['hsn_code'] ?? map['hsnCode'])?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      taxPerc: (map['tax_perc'] as num?)?.toDouble() ?? 0,
      totalAfterTax: (map['total_after_tax'] as num?)?.toDouble() ?? 0,
      isReturned: map['is_returned'] == true || map['is_returned'] == 1,
      categoryCode: map.containsKey('category_code') && map['category_code'] != null
          ? map['category_code'].toString()
          : (map.containsKey('category_id') && map['category_id'] != null
              ? map['category_id'].toString()
              : ''),
    );
  }
}
