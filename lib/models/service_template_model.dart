import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceFieldType {
  static const String textfield = 'textfield';
  static const String multiSelect = 'multi_select';
  static const String singleSelect = 'single_select';
  static const String textArea = 'text_area';
  static const String date = 'date';
  static const String pattern = 'pattern';

  static bool requiresOptions(String type) =>
      type == singleSelect || type == multiSelect;

  static bool supportsPrintOnReceipt(String type) => type != pattern;

  static const String patternValuePrefix = 'pattern_png:';

  static bool isPatternValue(dynamic value) {
    final raw = value?.toString() ?? '';
    return raw.startsWith(patternValuePrefix) &&
        raw.length > patternValuePrefix.length;
  }

  static String label(String type) {
    switch (type) {
      case textfield:
        return 'Text field';
      case multiSelect:
        return 'Multi select';
      case singleSelect:
        return 'Single select';
      case textArea:
        return 'Text area';
      case date:
        return 'Date';
      case pattern:
        return 'Pattern';
      default:
        return type;
    }
  }
}

class ServiceFieldModel {
  final String id;
  final String name;
  final String type;
  final List<String> options;
  final bool mandatory;
  final bool printable;
  final bool showInOrderSummary;

  const ServiceFieldModel({
    required this.id,
    required this.name,
    required this.type,
    this.options = const [],
    this.mandatory = false,
    this.printable = true,
    this.showInOrderSummary = false,
  });

  factory ServiceFieldModel.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['options'];
    final type = map['type']?.toString() ?? ServiceFieldType.textfield;
    return ServiceFieldModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      type: type,
      options: rawOptions is List
          ? rawOptions.map((e) => e.toString()).toList()
          : const [],
      mandatory: map['mandatory'] == true,
      printable: ServiceFieldType.supportsPrintOnReceipt(type)
          ? map['printable'] != false
          : false,
      showInOrderSummary: map['showInOrderSummary'] == true ||
          map['show_in_order_summary'] == true,
    );
  }
}

class ServiceTemplateCharge {
  final String id;
  final String name;
  final double rate;
  final double taxPerc;

  const ServiceTemplateCharge({
    required this.id,
    required this.name,
    required this.rate,
    this.taxPerc = 0,
  });

  factory ServiceTemplateCharge.fromMap(Map<String, dynamic> map) {
    final rawTax = map.containsKey('taxPerc') ? map['taxPerc'] : map['tax_perc'];
    return ServiceTemplateCharge(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      rate: (map['rate'] as num?)?.toDouble() ?? 0,
      taxPerc: (rawTax as num?)?.toDouble() ?? 0,
    );
  }
}

class ServiceTemplateModel {
  static const String defaultLabourCaption = 'Labour charge';

  final String id;
  final String name;
  final List<ServiceFieldModel> fields;
  final List<ServiceTemplateCharge> defaultCharges;
  final bool labourChargedByDefault;
  final String labourChargeCaption;
  final bool printServiceItemLabel;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServiceTemplateModel({
    required this.id,
    required this.name,
    required this.fields,
    this.defaultCharges = const [],
    this.labourChargedByDefault = true,
    this.labourChargeCaption = defaultLabourCaption,
    this.printServiceItemLabel = false,
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

  factory ServiceTemplateModel.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
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

    final defaultCharges = <ServiceTemplateCharge>[];
    final rawCharges = data['defaultCharges'] ?? data['default_charges'];
    if (rawCharges is List) {
      for (final entry in rawCharges) {
        if (entry is! Map) continue;
        final charge =
            ServiceTemplateCharge.fromMap(Map<String, dynamic>.from(entry));
        if (charge.id.isNotEmpty && charge.name.trim().isNotEmpty) {
          defaultCharges.add(charge);
        }
      }
    }

    final caption =
        (data['labourChargeCaption'] ?? data['labour_charge_caption'])
                ?.toString()
                .trim() ??
            '';

    return ServiceTemplateModel(
      id: id,
      name: data['name']?.toString() ?? '',
      fields: parsedFields,
      defaultCharges: defaultCharges,
      labourChargedByDefault:
          data['labourChargedByDefault'] is bool
              ? data['labourChargedByDefault'] as bool
              : data['labour_charged_by_default'] is bool
                  ? data['labour_charged_by_default'] as bool
                  : true,
      labourChargeCaption:
          caption.isEmpty ? defaultLabourCaption : caption,
      printServiceItemLabel: data['printServiceItemLabel'] == true ||
          data['print_service_item_label'] == true,
      createdAt: _parseDate(data['createdAt'] ?? data['created_at']),
      updatedAt: _parseDate(data['updatedAt'] ?? data['updated_at']),
    );
  }
}
