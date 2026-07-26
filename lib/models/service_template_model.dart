import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceFieldModel {
  final String id;
  final String name;
  final String type;
  final List<String> options;
  final bool mandatory;
  final bool printable;

  const ServiceFieldModel({
    required this.id,
    required this.name,
    required this.type,
    this.options = const [],
    this.mandatory = false,
    this.printable = true,
  });

  factory ServiceFieldModel.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['options'];
    return ServiceFieldModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? 'textfield',
      options: rawOptions is List ? rawOptions.map((e) => e.toString()).toList() : const [],
      mandatory: map['mandatory'] == true,
      printable: map['printable'] != false,
    );
  }
}

class ServiceTemplateModel {
  final String id;
  final String name;
  final List<ServiceFieldModel> fields;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServiceTemplateModel({
    required this.id,
    required this.name,
    required this.fields,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {}
    }
    if (value is DateTime) return value;
    return DateTime.now();
  }

  factory ServiceTemplateModel.fromFirestore(String id, Map<String, dynamic> data) {
    final rawFields = data['fields'];
    final List<ServiceFieldModel> parsedFields;
    if (rawFields is List) {
      parsedFields = rawFields
          .whereType<Map>()
          .map((e) => ServiceFieldModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      parsedFields = [];
    }

    return ServiceTemplateModel(
      id: id,
      name: data['name']?.toString() ?? '',
      fields: parsedFields,
      createdAt: _parseDate(data['createdAt'] ?? data['created_at']),
      updatedAt: _parseDate(data['updatedAt'] ?? data['updated_at']),
    );
  }
}
