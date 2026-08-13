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
    return BillItem(
      id: (map['id'] as num?)?.toInt(),
      billId: (map['bill_id'] as num?)?.toInt() ?? 0,
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
      hsnCode: map['hsn_code']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      returnQuantity: (map['return_quantity'] as num?)?.toDouble() ?? 0.0,
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      taxPerc: (map['tax_perc'] as num?)?.toDouble() ?? 0.0,
      totalAfterTax: (map['total_after_tax'] as num?)?.toDouble() ?? 0.0,
      isReturned: map['is_returned'] == 1 || map['is_returned'] == true,
      categoryCode:
          map['category_code']?.toString() ??
          map['category_id']?.toString() ??
          '',
    );
  }
}
