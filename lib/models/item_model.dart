import 'package:cloud_firestore/cloud_firestore.dart';

class ItemModel {
  int? id;
  final int? slNo;
  final String code;
  final String attributes;
  final String name;
  final double price;
  final double quantity;
  double availableQty;
  double? taxPerc;
  double sellPrice;
  final String categoryCode;
  String unit;
  bool printed;
  bool mapped;
  bool active;
  String? scannedBarcode = '';
  bool listedOnline;
  String additionalInfo;
  final String? description;
  final String? hsnCode;
  final DateTime createdAt;
  DateTime updatedAt;

  ItemModel({
    this.id,
    this.slNo,
    required this.sellPrice,
    required this.categoryCode,
    required this.code,
    required this.attributes,
    required this.name,
    required this.price,
    required this.quantity,
    required this.availableQty,
    required this.printed,
    required this.mapped,
    required this.active,
    this.scannedBarcode = '',
    this.unit = 'pcs',
    this.taxPerc,
    this.hsnCode,
    this.description,
    this.listedOnline = false,
    this.additionalInfo = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap({bool isRestoring = false}) {
    final map = {
      'id': id,
      'code': code,
      'name': name,
      'attributes': attributes,
      'price': price,
      'active': active ? 1 : 0,
      'sell_price': sellPrice,
      'quantity': quantity,
      'available_qty': availableQty,
      'printed': printed ? 1 : 0,
      'mapped': mapped ? 1 : 0,
      'category_code': categoryCode,
      'description': description,
      'tax_perc': taxPerc,
      'hsn_code': hsnCode,
      'unit': unit,
      'scanned_barcode': scannedBarcode,
      'listed_online': listedOnline ? 1 : 0,
      'additional_info': additionalInfo,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    return map;
  }

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    return ItemModel(
      id: map['id'] as int?,
      slNo: map['sl_no'] as int?,
      name: map['name'] as String,
      code: map['code'] as String,
      price: map['price'] as double,
      sellPrice: map['sell_price'] as double,
      quantity: map['quantity'] as double,
      availableQty: -1,
      printed: (map['printed'] as int) == 1, // Convert int back to bool
      mapped: map['mapped'] != null
          ? (map['mapped'] as int) == 1
          : false, // Convert int back to bool

      active: map.containsKey('active') && map['active'] != null
          ? (map['active'] as int) == 1
          : true,
      attributes: map.containsKey('attributes') && map['attributes'] != null
          ? (map['attributes'] as String)
          : '',
      categoryCode:
          map.containsKey('category_code') && map['category_code'] != null
          ? map['category_code'] as String
          : (map.containsKey('category_id') && map['category_id'] != null
                ? map['category_id'].toString()
                : ''),
      additionalInfo:
          map.containsKey('additional_info') && map['additional_info'] != null
          ? map['additional_info'] as String
          : '',
      listedOnline:
          map.containsKey('listed_online') && map['listed_online'] != null
          ? (map['listed_online'] as int) == 1
          : false,
      taxPerc: map['tax_perc'] as double?,
      hsnCode: map['hsn_code'] as String?,
      description: map['description'] as String?,

      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.now(),
    );
  }

  factory ItemModel.fromFirestore(DocumentSnapshot doc) {
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

    return ItemModel(
      id: data['id'] as int?,
      slNo: data['sl_no'] as int?,
      name: data['name'] as String? ?? '',
      code: data['code'] as String? ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      sellPrice: (data['sell_price'] as num?)?.toDouble() ?? 0.0,
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0.0,
      availableQty: (data['available_qty'] as num?)?.toDouble() ?? 0.0,
      printed: data['printed'] == true || data['printed'] == 1,
      mapped: data['mapped'] == true || data['mapped'] == 1,
      active: data['active'] != false && data['active'] != 0,
      attributes: data['attributes'] as String? ?? '',
      categoryCode: data['category_code'] as String? ?? '',
      unit: data['unit'] as String? ?? 'pcs',
      scannedBarcode: data['scanned_barcode'] as String? ?? '',
      listedOnline: data['listed_online'] == true || data['listed_online'] == 1,
      additionalInfo: data['additional_info'] as String? ?? '',
      taxPerc: (data['tax_perc'] as num?)?.toDouble(),
      hsnCode: data['hsn_code'] as String?,
      description: data['description'] as String?,
      createdAt: _parseTimestamp(data['created_at']) ?? DateTime.now(),
      updatedAt: _parseTimestamp(data['updated_at']) ?? DateTime.now(),
    );
  }
}
