import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  /// Firestore document id of this user document (`users/{docId}`).
  final String? docId;
  final String? userId;
  final String? name;
  final String? email;
  final String? phone;
  final String? address;
  final String? gstNumber;
  final String? role;
  final String? activeDevice;
  final DateTime? accountExpiry;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastLogin;
  final DateTime? lastSyncTime;
  final int? billVersion;
  final int? itemVersion;
  final bool? resetSyncTime;
  final bool? uploadErrorLog;

  UserModel({
    this.docId,
    this.userId,
    this.name,
    this.email,
    this.phone,
    this.address,
    this.gstNumber,
    this.role,
    this.activeDevice,
    this.accountExpiry,
    this.createdAt,
    this.updatedAt,
    this.lastLogin,
    this.lastSyncTime,
    this.billVersion,
    this.itemVersion,
    this.resetSyncTime,
    this.uploadErrorLog,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    
    final data = doc.data() as Map<String, dynamic>?;

    return UserModel(
      docId: doc.id,
      userId: data?['userId'] as String?,
      name: data?['name'] as String?,
      email: data?['email'] as String?,
      phone: data?['phone'] as String?,
      address: data?['address'] as String?,
      gstNumber: data?['gstNumber'] as String?,
      role: data?['role'] as String?,
      // Use toString() so non-string values (e.g. map, int) still show up
      activeDevice: data?['activeDevice']?.toString(),
      accountExpiry: (data?['accountExpiry'] as Timestamp?)?.toDate(),
      createdAt: (data?['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data?['updatedAt'] as Timestamp?)?.toDate(),
      lastLogin: (data?['lastLogin'] as Timestamp?)?.toDate(),
      lastSyncTime: (data?['lastSyncTime'] as Timestamp?)?.toDate(),
      billVersion: data?['bill_version'] as int?,
      itemVersion: data?['item_version'] as int?,
      resetSyncTime: data?['resetSyncTime'] as bool?,
      uploadErrorLog: data?['uploadErrorLog'] as bool?,
    );
  }

  String formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
