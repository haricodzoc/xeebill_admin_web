import 'package:cloud_firestore/cloud_firestore.dart';

import 'service_order_item_model.dart';

enum ServiceStatus {
  pending,
  inProgress,
  completed;

  String get dbValue {
    switch (this) {
      case ServiceStatus.pending:
        return 'pending';
      case ServiceStatus.inProgress:
        return 'inprogress';
      case ServiceStatus.completed:
        return 'completed';
    }
  }

  String get label {
    switch (this) {
      case ServiceStatus.pending:
        return 'Pending';
      case ServiceStatus.inProgress:
        return 'In progress';
      case ServiceStatus.completed:
        return 'Completed';
    }
  }

  static ServiceStatus fromString(String? raw) {
    final v = (raw ?? '').toLowerCase().replaceAll(' ', '').replaceAll('_', '');
    switch (v) {
      case 'inprogress':
        return ServiceStatus.inProgress;
      case 'completed':
        return ServiceStatus.completed;
      default:
        return ServiceStatus.pending;
    }
  }

  static List<ServiceStatus> get selectableValues => ServiceStatus.values;
}

class ServiceOrderModel {
  String? docId;
  int? id;
  String serviceCode;
  String customerCode;
  String customerName;
  String customerPhone;
  String type;
  String status;
  int orderNo;
  String financialYear;
  String serviceNumber;
  DateTime serviceDate;
  DateTime serviceTime;
  double subTotal;
  double grandTotal;
  double netPayable;
  int totalItems;
  String profileId;
  String profileCode;
  String lastUpdatedProfile;
  String additionalInfo;
  String paymentMode;
  double advanceAmount;
  DateTime dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  List<ServiceOrderItemModel>? items;

  ServiceOrderModel({
    this.docId,
    this.id,
    required this.serviceCode,
    required this.customerCode,
    this.customerName = '',
    this.customerPhone = '',
    required this.type,
    required this.status,
    required this.orderNo,
    required this.financialYear,
    required this.serviceNumber,
    required this.serviceDate,
    required this.serviceTime,
    required this.subTotal,
    required this.grandTotal,
    required this.netPayable,
    required this.totalItems,
    required this.profileId,
    required this.profileCode,
    required this.lastUpdatedProfile,
    required this.additionalInfo,
    required this.paymentMode,
    required this.advanceAmount,
    required this.dueDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.items,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  ServiceStatus get serviceStatus => ServiceStatus.fromString(status);

  bool get isCompleted => serviceStatus == ServiceStatus.completed;

  String get displayStatus => serviceStatus.label;

  static DateTime _parseTimestamp(dynamic timestamp, DateTime fallback) {
    if (timestamp == null) return fallback;
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is String) {
      try {
        return DateTime.parse(timestamp);
      } catch (_) {
        return fallback;
      }
    }
    if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
    return fallback;
  }

  static List<ServiceOrderItemModel> _parseItems(dynamic raw) {
    if (raw is! List) return [];
    final items = <ServiceOrderItemModel>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        items.add(ServiceOrderItemModel.fromMap(Map<String, dynamic>.from(entry)));
      } catch (_) {}
    }
    return items;
  }

  factory ServiceOrderModel.fromMap(Map<String, dynamic> map, {String? docId}) {
    final now = DateTime.now();
    return ServiceOrderModel(
      docId: docId,
      id: map['id'] is int ? map['id'] as int? : int.tryParse(map['id']?.toString() ?? ''),
      serviceCode: map['service_code']?.toString() ?? '',
      customerCode: map['customer_code']?.toString() ?? '',
      customerName: map['customer_name']?.toString() ?? '',
      customerPhone: map['customer_phone']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      orderNo: (map['order_no'] as num?)?.toInt() ?? 0,
      financialYear: map['financial_year']?.toString() ?? '',
      serviceNumber: map['service_number']?.toString() ?? '',
      serviceDate: _parseTimestamp(map['service_date'], now),
      serviceTime: _parseTimestamp(map['service_time'], now),
      subTotal: (map['sub_total'] as num?)?.toDouble() ?? 0,
      grandTotal: (map['grand_total'] as num?)?.toDouble() ?? 0,
      netPayable: (map['net_payable'] as num?)?.toDouble() ?? 0,
      totalItems: (map['total_items'] as num?)?.toInt() ?? 0,
      profileId: map['profile_id']?.toString() ?? '',
      profileCode: map['profile_code']?.toString() ?? '',
      lastUpdatedProfile: map['last_updated_profile']?.toString() ?? '',
      additionalInfo: map['additional_info']?.toString() ?? '',
      paymentMode: map['payment_mode']?.toString() ?? '',
      advanceAmount: (map['advance_amount'] as num?)?.toDouble() ?? 0,
      dueDate: _parseTimestamp(map['due_date'], now),
      createdAt: _parseTimestamp(map['created_at'], now),
      updatedAt: _parseTimestamp(map['updated_at'], now),
      items: _parseItems(map['items']),
    );
  }

  factory ServiceOrderModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Service order document data is null');
    }
    return ServiceOrderModel.fromMap(data, docId: doc.id);
  }
}
