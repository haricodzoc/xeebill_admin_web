// lib/models/bill_item.dart

class BillItem {
  int? id;
  int billId;
  String code;
  String name;
  String unit;
  String hsnCode;
  String categoryCode;
  double price;
  double quantity;
  double returnQuantity;
  double originalQuantity;
  double total;
  double taxPerc;
  double totalAfterTax;
  bool isReturned;

  BillItem({
    this.id,
    required this.billId,
    required this.name,
    required this.hsnCode,
    required this.unit,
    required this.categoryCode,
    required this.code,
    required this.price,
    required this.quantity,
    required this.returnQuantity,
    required this.total,
    required this.taxPerc,
    required this.totalAfterTax,
    required this.isReturned,
    this.originalQuantity = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bill_id': billId,
      'code': code,
      'name': name,
      'hsn_code': hsnCode,
      'unit': unit,
      'price': price,
      'quantity': quantity,
      'return_quantity': returnQuantity,
      'total': total,
      'tax_perc': taxPerc,
      'total_after_tax': totalAfterTax,
      'is_returned': isReturned ? 1 : 0,
      'category_code': categoryCode,
    };
  }

  factory BillItem.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    String asString(dynamic v) => v?.toString() ?? '';

    return BillItem(
      id: (map['id'] as num?)?.toInt(),
      billId: (map['bill_id'] as num?)?.toInt() ??
          (map['billId'] as num?)?.toInt() ??
          0,
      code: asString(map['code']),
      name: asString(map['name']),
      unit: asString(map['unit']),
      hsnCode: asString(map['hsn_code'] ?? map['hsnCode']),
      price: asDouble(map['price']),
      quantity: asDouble(map['quantity']),
      returnQuantity: asDouble(map['return_quantity'] ?? map['returnQuantity']),
      total: asDouble(map['total']),
      taxPerc: asDouble(map['tax_perc'] ?? map['taxPerc']),
      totalAfterTax: asDouble(map['total_after_tax'] ?? map['totalAfterTax']),
      isReturned: map['is_returned'] == 1 ||
          map['is_returned'] == true ||
          map['isReturned'] == true,
      categoryCode: asString(
        map['category_code'] ?? map['categoryCode'] ?? map['category_id'],
      ),
      originalQuantity:
          asDouble(map['original_quantity'] ?? map['originalQuantity']),
    );
  }
}
