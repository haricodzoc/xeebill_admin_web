import 'package:cloud_firestore/cloud_firestore.dart';

class RechargePlanModel {
  final String id;
  final int backupYear;
  final int bills;
  final int customers;
  final int devices;
  final int discount;
  final int durationInDays;
  final int items;
  final int locationLimit;
  final String planId;
  final int price;
  final int services;
  final String subscriptionId;
  final String subtitle;
  final String title;

  RechargePlanModel({
    required this.id,
    required this.backupYear,
    required this.bills,
    required this.customers,
    required this.devices,
    required this.discount,
    required this.durationInDays,
    required this.items,
    required this.locationLimit,
    required this.planId,
    required this.price,
    required this.services,
    required this.subscriptionId,
    required this.subtitle,
    required this.title,
  });

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  static int _toIntOrDefault(dynamic value, {int defaultValue = 1}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value.toString());
    return parsed ?? defaultValue;
  }

  static int _readBackupYear(Map<String, dynamic>? data) {
    if (data == null) return 0;
    if (data.containsKey('backup_year')) {
      return _toInt(data['backup_year']);
    }
    // Legacy typo key from earlier admin builds.
    if (data.containsKey('backup_yesr')) {
      return _toInt(data['backup_yesr']);
    }
    return 0;
  }

  factory RechargePlanModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic> ? raw : null;
    return RechargePlanModel(
      id: doc.id,
      backupYear: _readBackupYear(data),
      bills: _toInt(data?['bills']),
      customers: _toInt(data?['customers']),
      devices: _toInt(data?['devices']),
      discount: _toInt(data?['discount']),
      durationInDays: _toInt(data?['duration_in_days']),
      items: _toInt(data?['items']),
      locationLimit: _toIntOrDefault(data?['location_limit']),
      planId: data?['plan_id']?.toString() ?? '',
      price: _toInt(data?['price']),
      services: _toInt(data?['services']),
      subscriptionId: data?['subscription_id']?.toString() ?? '',
      subtitle: data?['subtitle']?.toString() ?? '',
      title: data?['title']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'backup_year': backupYear,
      'bills': bills,
      'customers': customers,
      'devices': devices,
      'discount': discount,
      'duration_in_days': durationInDays,
      'items': items,
      'location_limit': locationLimit,
      'plan_id': planId,
      'price': price,
      'services': services,
      'subscription_id': subscriptionId,
      'subtitle': subtitle,
      'title': title,
    };
  }
}
