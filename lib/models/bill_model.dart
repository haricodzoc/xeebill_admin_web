// lib/models/bill.dart

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:xeebill_web/utils/constants.dart';
import 'bill_item_model.dart';

class BillModel {
  int? id;
  String billCode;
  String customerCode;
  String customerName;
  String customerGst;
  String customerAddress;
  String type;
  int billNo;
  String invoiceNumber; // Added invoiceNo field
  String financialYear; // Added financialYear field
  double subTotal;
  double discount;
  double grandTotal;
  double returnTotal;
  double netPayable;
  int totalItems;
  int totalReturnItems;
  bool completed;
  DateTime billDate;
  DateTime billTime;
  String profileId;
  String profileCode;
  String lastUpdatedProfile;
  String paymentMode;
  double creditAmount;
  String additionalInfo;
  List<BillItem>? items;
  DateTime dueDate;
  /// From `location_id` / `locationId` when present on the bill document.
  final String? locationId;
  final DateTime createdAt;
  final DateTime updatedAt;

  BillModel({
    this.id,
    required this.billCode,
    required this.customerCode,
    this.customerName = '',
    this.customerGst = '',
    this.customerAddress = '',
    required this.billNo,
    required this.type,
    required this.invoiceNumber, // Initialize invoiceNo
    required this.financialYear, // Initialize financialYear
    required this.billDate,
    required this.billTime,
    required this.subTotal,
    required this.discount,
    required this.grandTotal,
    required this.totalItems,
    required this.totalReturnItems,
    required this.returnTotal,
    required this.netPayable,
    required this.completed,
    required this.profileId,
    required this.profileCode,
    required this.paymentMode,
    required this.creditAmount,
    required this.additionalInfo,
    required this.lastUpdatedProfile,
    required this.dueDate,
    this.items,
    this.locationId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  // Explicitly defining the return type as Map<String, dynamic>
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bill_code': billCode,
      'customer_code': customerCode,
      'bill_no': billNo,
      'type': type,
      'invoice_number': invoiceNumber, // Store invoiceNo in the database
      'financial_year': financialYear, // Store financialYear in the database
      'sub_total': subTotal,
      'discount': discount,
      'grand_total': grandTotal,
      'total_items': totalItems,
      'total_return_items': totalReturnItems,
      'return_total': returnTotal,
      'net_payable': netPayable,
      'completed': completed ? 1 : 0, //  printed is stored as an integer
      'bill_date': billDate.toIso8601String(),
      'bill_time': billTime.toIso8601String(),
      'profile_id': profileId,
      'profile_code': profileCode,
      'last_updated_profile': lastUpdatedProfile,
      'payment_mode': paymentMode,
      'credit_amount': creditAmount,
      'additional_info': jsonEncode(additionalInfo),
      'due_date': dueDate.toIso8601String(),
      if (locationId != null && locationId!.trim().isNotEmpty) 'location_id': locationId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Special toMap for updates (excludes created_at)
  Map<String, dynamic> toMapForUpdate() {
    final map = toMap();
    map.remove('created_at'); // Remove created_at from update operations
    map['updated_at'] = DateTime.now()
        .toIso8601String(); // Force update timestamp
    return map;
  }

  factory BillModel.fromMap(Map<String, dynamic> map) {
    return BillModel(
      id: map['id'],
      billCode: map.containsKey('bill_code') && map['bill_code'] != null
          ? map['bill_code']
          : '',
      customerCode: map['customer_code'] ?? '',
      customerName: map['customer_name'] ?? '',
      customerGst: map['customer_gst'] ?? '',
      customerAddress: map['customer_address'] ?? '',
      billNo: map['bill_no'],
      type: map['type'] ?? GstType.composite.toString(),
      invoiceNumber:
          map['invoice_number'], // Retrieve invoiceNo from the database
      financialYear:
          map['financial_year'], // Retrieve financialYear from the database
      subTotal: map['sub_total'],
      discount: map['discount'],
      grandTotal: map['grand_total'],
      totalItems: map['total_items'],
      totalReturnItems: map['total_return_items'] ?? 0, // Handle optional field
      returnTotal: map['return_total'] ?? 0.0, // Handle optional field
      netPayable: map['net_payable'] ?? 0.0, // Handle
      completed: map['completed'] == 1, //  printed is stored as an integer
      billDate: DateTime.parse(map['bill_date']),
      billTime: DateTime.parse(map['bill_time']),
      profileId: map['profile_id'] ?? '',
      profileCode: map['profile_code'] ?? '',
      lastUpdatedProfile: map['last_updated_profile'] ?? '',
      paymentMode:
          map.containsKey('payment_mode') && map['payment_mode'] != null
          ? map['payment_mode']
          : PaymentModes.cash.toString(),
      creditAmount:
          map.containsKey('credit_amount') && map['credit_amount'] != null
          ? (map['credit_amount'] as num).toDouble()
          : 0.0,
      additionalInfo:
          map.containsKey('additional_info') && map['additional_info'] != null
          ? (jsonDecode(map['additional_info']))
          : '',
      dueDate: map.containsKey('due_date') && map['due_date'] != null
          ? DateTime.parse(map['due_date'])
          : DateTime.now(),
      locationId: () {
        final v = map['location_id'] ?? map['locationId'];
        if (v == null) return null;
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }(),
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      items: [],
    );
  }

  factory BillModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Bill document data is null');
    }

    // Helper to parse timestamp
    DateTime _parseTimestamp(dynamic timestamp, DateTime fallback) {
      if (timestamp == null) return fallback;
      if (timestamp is Timestamp) {
        return timestamp.toDate();
      } else if (timestamp is String) {
        try {
          return DateTime.parse(timestamp);
        } catch (e) {
          return fallback;
        }
      } else if (timestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return fallback;
    }

    return BillModel(
      id: data['id'] as int?,
      billCode: data['bill_code'] as String? ?? '',
      customerCode: data['customer_code'] as String? ?? '',
      customerName: data['customer_name'] as String? ?? '',
      customerGst: data['customer_gst'] as String? ?? '',
      customerAddress: data['customer_address'] as String? ?? '',
      billNo: (data['bill_no'] as num?)?.toInt() ?? 0,
      type: data['type'] as String? ?? GstType.composite.toString(),
      invoiceNumber: data['invoice_number'] as String? ?? '',
      financialYear: data['financial_year'] as String? ?? '',
      subTotal: (data['sub_total'] as num?)?.toDouble() ?? 0.0,
      discount: (data['discount'] as num?)?.toDouble() ?? 0.0,
      grandTotal: (data['grand_total'] as num?)?.toDouble() ?? 0.0,
      totalItems: (data['total_items'] as num?)?.toInt() ?? 0,
      totalReturnItems: (data['total_return_items'] as num?)?.toInt() ?? 0,
      returnTotal: (data['return_total'] as num?)?.toDouble() ?? 0.0,
      netPayable: (data['net_payable'] as num?)?.toDouble() ?? 0.0,
      completed: data['completed'] == true || data['completed'] == 1,
      billDate: _parseTimestamp(
        data['bill_date'] ?? data['billDate'],
        DateTime.now(),
      ),
      billTime: _parseTimestamp(
        data['bill_time'] ?? data['billTime'],
        DateTime.now(),
      ),
      profileId: data['profile_id'] as String? ?? '',
      profileCode: data['profile_code'] as String? ?? '',
      lastUpdatedProfile: data['last_updated_profile'] as String? ?? '',
      paymentMode:
          data['payment_mode'] as String? ?? PaymentModes.cash.toString(),
      creditAmount: (data['credit_amount'] as num?)?.toDouble() ?? 0.0,
      additionalInfo: data['additional_info'] != null
          ? (data['additional_info'] is String
                ? (data['additional_info'] as String).isNotEmpty
                      ? jsonDecode(data['additional_info'] as String)
                      : ''
                : data['additional_info'].toString())
          : '',
      dueDate: _parseTimestamp(data['due_date'], DateTime.now()),
      locationId: () {
        final loc = data['location_id'] ?? data['locationId'];
        if (loc == null) return null;
        final s = loc.toString().trim();
        return s.isEmpty ? null : s;
      }(),
      createdAt: _parseTimestamp(data['created_at'], DateTime.now()),
      updatedAt: _parseTimestamp(data['updated_at'], DateTime.now()),
      items: _parseItems(data['items']),
    );
  }

  // Helper to parse items from JSON
  static List<BillItem>? _parseItems(dynamic itemsData) {
    if (itemsData == null) return null;

    try {
      List<BillItem> items = [];

      // If items is a String (JSON string), parse it first
      if (itemsData is String) {
        final decoded = jsonDecode(itemsData);
        if (decoded is List) {
          for (var item in decoded) {
            if (item is Map<String, dynamic>) {
              items.add(BillItem.fromMap(item));
            }
          }
        }
      }
      // If items is already a List
      else if (itemsData is List) {
        for (var item in itemsData) {
          if (item is Map<String, dynamic>) {
            items.add(BillItem.fromMap(item));
          }
        }
      }

      return items.isEmpty ? null : items;
    } catch (e) {
      debugPrint('Error parsing bill items: $e');
      return null;
    }
  }
}
