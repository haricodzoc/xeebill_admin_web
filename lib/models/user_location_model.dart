import 'package:cloud_firestore/cloud_firestore.dart';

/// User business location under `users/{userId}/locations/{locationId}`.
class UserLocationModel {
  final String id;
  final String name;
  final String businessName;
  final String businessPhoneNumber;
  final String businessGstNumber;
  final String gstType;
  final String address;
  final List<String> subProfileIds;
  /// Firestore `isDefault` / `is_default`. Default location is account fallback.
  final bool isDefault;

  UserLocationModel({
    required this.id,
    required this.name,
    required this.businessName,
    required this.businessPhoneNumber,
    required this.businessGstNumber,
    required this.gstType,
    required this.address,
    required this.subProfileIds,
    this.isDefault = false,
  });

  static List<String> _parseSubProfileIds(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [];
  }

  static String _str(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return '';
  }

  static bool _readBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  factory UserLocationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? <String, dynamic>{};
    final isDefault = _readBool(d['isDefault'] ?? d['is_default']) ||
        doc.id.trim().toLowerCase() == 'default';
    return UserLocationModel(
      id: doc.id,
      name: _str(d, ['name']),
      businessName: _str(d, ['businessName', 'business_name']),
      businessPhoneNumber: _str(d, [
        'businessPhoneNumber',
        'business_phone_number',
      ]),
      businessGstNumber: _str(d, [
        'businessGstNumber',
        'business_gst_number',
      ]),
      gstType: _str(d, ['gstType', 'gst_type']),
      address: _str(d, ['address']),
      subProfileIds: _parseSubProfileIds(
        d['subProfileIds'] ?? d['sub_profile_ids'],
      ),
      isDefault: isDefault,
    );
  }
}
