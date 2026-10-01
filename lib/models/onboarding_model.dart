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

class OnboardingRemark {
  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OnboardingRemark({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get wasEdited =>
      updatedAt.difference(createdAt).inSeconds.abs() > 1;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  OnboardingRemark copyWith({
    String? text,
    DateTime? updatedAt,
  }) {
    return OnboardingRemark(
      id: id,
      text: text ?? this.text,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static OnboardingRemark? fromDynamic(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final text = (map['text'] ?? map['remark'] ?? '').toString().trim();
    if (text.isEmpty) return null;
    final created = OnboardingModel.parseDate(map['createdAt']) ?? DateTime.now();
    final updated = OnboardingModel.parseDate(map['updatedAt']) ?? created;
    final id = (map['id'] ?? '').toString().trim();
    return OnboardingRemark(
      id: id.isEmpty ? created.microsecondsSinceEpoch.toString() : id,
      text: text,
      createdAt: created,
      updatedAt: updated,
    );
  }
}

class OnboardingModel {
  final String id;
  final String name;
  final String address;
  final String location;
  final String phone;
  final String shopType;
  /// Joined text of [remarkNotes], kept for search and older readers.
  final String remarks;
  final List<OnboardingRemark> remarkNotes;
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
    this.remarkNotes = const [],
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
      'remarkNotes': remarkNotes.map((note) => note.toMap()).toList(),
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
    final createdAt = _parseDate(data['createdAt']) ?? DateTime.now();
    final updatedAt = _parseDate(data['updatedAt']) ?? createdAt;
    final legacyRemarks = (data['remarks'] ?? '').toString().trim();
    final notes = _parseRemarkNotes(
      data['remarkNotes'] ?? data['remark_notes'],
      legacyRemarks: legacyRemarks,
      fallbackDate: updatedAt,
    );
    return OnboardingModel(
      id: doc.id,
      name: (data['name'] ?? '').toString().trim(),
      address: (data['address'] ?? '').toString().trim(),
      location: (data['location'] ?? '').toString().trim(),
      phone: (data['phone'] ?? '').toString().trim(),
      shopType: (data['shopType'] ?? data['shop_type'] ?? '').toString().trim(),
      remarks: notes.isEmpty
          ? legacyRemarks
          : notes.map((note) => note.text).join('\n'),
      remarkNotes: notes,
      status: OnboardingStatus.fromValue(data['status']),
      recentEnquiryDate: _parseDate(
        data['recentEnquiryDate'] ?? data['recent_enquiry_date'],
      ),
      acceptedImplementationDate: _parseDate(
        data['acceptedImplementationDate'] ??
            data['accepted_implementation_date'],
      ),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static List<OnboardingRemark> _parseRemarkNotes(
    dynamic raw, {
    required String legacyRemarks,
    required DateTime fallbackDate,
  }) {
    final notes = <OnboardingRemark>[];
    if (raw is List) {
      for (final entry in raw) {
        final note = OnboardingRemark.fromDynamic(entry);
        if (note != null) notes.add(note);
      }
    }
    if (notes.isEmpty && legacyRemarks.isNotEmpty) {
      notes.add(
        OnboardingRemark(
          id: 'legacy',
          text: legacyRemarks,
          createdAt: fallbackDate,
          updatedAt: fallbackDate,
        ),
      );
    }
    notes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notes;
  }

  OnboardingModel copyWith({
    String? name,
    String? address,
    String? location,
    String? phone,
    String? shopType,
    String? remarks,
    List<OnboardingRemark>? remarkNotes,
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
      remarks: remarks ??
          (remarkNotes == null
              ? this.remarks
              : remarkNotes.map((note) => note.text).join('\n')),
      remarkNotes: remarkNotes ?? this.remarkNotes,
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

  static DateTime? parseDate(dynamic value) => _parseDate(value);

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}
