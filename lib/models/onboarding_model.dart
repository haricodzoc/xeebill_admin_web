import 'package:cloud_firestore/cloud_firestore.dart';

enum OnboardingStatus {
  pending,
  inProgress,
  completed;

  String get firestoreValue {
    switch (this) {
      case OnboardingStatus.pending:
        return 'pending';
      case OnboardingStatus.inProgress:
        return 'inprogress';
      case OnboardingStatus.completed:
        return 'completed';
    }
  }

  String get label {
    switch (this) {
      case OnboardingStatus.pending:
        return 'Pending';
      case OnboardingStatus.inProgress:
        return 'In Progress';
      case OnboardingStatus.completed:
        return 'Completed';
    }
  }

  static OnboardingStatus fromValue(dynamic raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case 'inprogress':
      case 'in_progress':
      case 'in-progress':
        return OnboardingStatus.inProgress;
      case 'completed':
      case 'complete':
      case 'done':
        return OnboardingStatus.completed;
      case 'pending':
      default:
        return OnboardingStatus.pending;
    }
  }
}

const List<String> kOnboardingShopTypes = [
  'Textiles',
  'Mobile Phones',
  'Milk & Dairy',
  'Footwear',
  'Fruits & Vegetables',
  'Spare Parts',
  'Saloon & Beauty Parlour',
  'Restaurant',
  'Paints & Varnishes',
  'Food & Beverages',
  'Furniture',
  'Hardware',
  'Health & Beauty',
  'Home & Kitchen',
  'Jewellery',
  'Laptops & Computers',
  'Mobile Phones',
  'Music & Movies',
  'Office Supplies',
  'Pet Supplies',
  'Pharmacy',
  'Sports & Outdoors',
  'Toys & Games',
  'Travel & Luggage',
  'Super Market',
  'Opticals',
  'Vegetables',
  'Stationery',
  'Grocery',
  'Electronics',
  'Hardware',
  'Pharmacy',
  'Jewellery',
  'Bakery',
  'Others',
];

class OnboardingModel {
  final String id;
  final String name;
  final String address;
  final String location;
  final String phone;
  final String shopType;
  final String remarks;
  final OnboardingStatus status;
  final DateTime? recentEnquiryDate;
  final DateTime? acceptedImplementationDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OnboardingModel({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    required this.phone,
    required this.shopType,
    required this.remarks,
    required this.status,
    this.recentEnquiryDate,
    this.acceptedImplementationDate,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'location': location,
      'phone': phone,
      'shopType': shopType,
      'remarks': remarks,
      'status': status.firestoreValue,
      'recentEnquiryDate': recentEnquiryDate == null
          ? null
          : Timestamp.fromDate(recentEnquiryDate!),
      'acceptedImplementationDate': acceptedImplementationDate == null
          ? null
          : Timestamp.fromDate(acceptedImplementationDate!),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory OnboardingModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return OnboardingModel(
      id: doc.id,
      name: (data['name'] ?? '').toString().trim(),
      address: (data['address'] ?? '').toString().trim(),
      location: (data['location'] ?? '').toString().trim(),
      phone: (data['phone'] ?? '').toString().trim(),
      shopType: (data['shopType'] ?? data['shop_type'] ?? '').toString().trim(),
      remarks: (data['remarks'] ?? '').toString().trim(),
      status: OnboardingStatus.fromValue(data['status']),
      recentEnquiryDate: _parseDate(
        data['recentEnquiryDate'] ?? data['recent_enquiry_date'],
      ),
      acceptedImplementationDate: _parseDate(
        data['acceptedImplementationDate'] ??
            data['accepted_implementation_date'],
      ),
      createdAt: _parseDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(data['updatedAt']) ?? DateTime.now(),
    );
  }

  OnboardingModel copyWith({
    String? name,
    String? address,
    String? location,
    String? phone,
    String? shopType,
    String? remarks,
    OnboardingStatus? status,
    DateTime? recentEnquiryDate,
    DateTime? acceptedImplementationDate,
    DateTime? updatedAt,
    bool clearRecentEnquiryDate = false,
    bool clearAcceptedImplementationDate = false,
  }) {
    return OnboardingModel(
      id: id,
      name: name ?? this.name,
      address: address ?? this.address,
      location: location ?? this.location,
      phone: phone ?? this.phone,
      shopType: shopType ?? this.shopType,
      remarks: remarks ?? this.remarks,
      status: status ?? this.status,
      recentEnquiryDate: clearRecentEnquiryDate
          ? null
          : (recentEnquiryDate ?? this.recentEnquiryDate),
      acceptedImplementationDate: clearAcceptedImplementationDate
          ? null
          : (acceptedImplementationDate ?? this.acceptedImplementationDate),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}
