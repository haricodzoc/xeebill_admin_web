import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/functions.dart';

class SubProfileModel {
  String id;
  String prefix;
  String name;
  String code;
  String avatar;
  String pin;
  String status;
  DateTime? lastSyncTime;
  DateTime? categorySyncTime;
  DateTime? billSyncTime;
  DateTime? itemSyncTime;
  DateTime? itemMappingSyncTime;
  DateTime? discountSyncTime;
  DateTime? updatedAt;

  SubProfileModel({
    required this.id,
    required this.prefix,
    required this.name,
    required this.code,
    required this.avatar,
    required this.pin,
    required this.status,
    this.lastSyncTime,
    this.itemSyncTime,
    this.categorySyncTime,
    this.billSyncTime,
    this.itemMappingSyncTime,
    this.discountSyncTime,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'prefix': prefix,
      'name': name,
      'code': code,
      'avatar': avatar,
      'pin': pin,
      'status': status,
      'lastSyncTime': lastSyncTime?.toIso8601String(),
      'itemSyncTime': itemSyncTime?.toIso8601String(),
      'categorySyncTime': categorySyncTime?.toIso8601String(),
      'billSyncTime': billSyncTime?.toIso8601String(),
      'itemMappingSyncTime': itemMappingSyncTime?.toIso8601String(),
      'discountSyncTime': discountSyncTime?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory SubProfileModel.fromMap(Map<String, dynamic> map, String docId) {
    return SubProfileModel(
      id: docId,
      prefix: map['prefix']?.toString() ?? '',
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      avatar: map['avatar'] ?? 'default',
      pin: map['pin'] ?? '',
      status: map['status'] ?? 'inactive',
      lastSyncTime: _parseTimestamp(map['lastSyncTime']),
      itemSyncTime: _parseTimestamp(map['itemSyncTime']),
      categorySyncTime: _parseTimestamp(map['categorySyncTime']),
      billSyncTime: _parseTimestamp(map['billSyncTime']),
      itemMappingSyncTime: _parseTimestamp(map['itemMappingSyncTime']),
      discountSyncTime: _parseTimestamp(map['discountSyncTime']),
      updatedAt: _parseTimestamp(map['updatedAt']),
    );
  }

  // Helper method to safely parse Firestore Timestamp to DateTime
  static DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;

    if (timestamp is Timestamp) {
      // Firestore Timestamp
      return timestamp.toDate();
    } else if (timestamp is String) {
      // ISO String format
      try {
        return DateTime.parse(timestamp);
      } catch (e) {
        debugPrint('Error parsing timestamp string: $e');
        logErrorToFile(e.toString(), StackTrace.current);
        return null;
      }
    } else if (timestamp is int) {
      // Unix timestamp (milliseconds)
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }

    debugPrint('Unknown timestamp format: ${timestamp.runtimeType}');
    return null;
  }
}
