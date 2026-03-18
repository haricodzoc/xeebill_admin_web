import 'package:cloud_firestore/cloud_firestore.dart';

class RechargePlanModel {
  final String id;
  final double discount;
  final int durationInDays;
  final String planId;
  final double price;
  final String subscriptionId;
  final String subtitle;
  final String title;

  RechargePlanModel({
    required this.id,
    required this.discount,
    required this.durationInDays,
    required this.planId,
    required this.price,
    required this.subscriptionId,
    required this.subtitle,
    required this.title,
  });

  factory RechargePlanModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RechargePlanModel(
      id: doc.id,
      discount: (data['discount'] ?? 0.0).toDouble(),
      durationInDays: data['duration_in_days'] ?? 0,
      planId: data['plan_id'] ?? '',
      price: (data['price'] ?? 0.0).toDouble(),
      subscriptionId: data['subscription_id'] ?? '',
      subtitle: data['subtitle'] ?? '',
      title: data['title'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'discount': discount,
      'duration_in_days': durationInDays,
      'plan_id': planId,
      'price': price,
      'subscription_id': subscriptionId,
      'subtitle': subtitle,
      'title': title,
    };
  }
}
