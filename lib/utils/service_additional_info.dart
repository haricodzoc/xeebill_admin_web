import 'dart:convert';

import '../models/service_template_model.dart';

class ServiceAdditionalInfo {
  final String? templateId;
  final String? templateName;
  final Map<String, dynamic> customFields;
  final List<ServiceFieldModel> fieldDefinitions;
  final bool printServiceItemLabel;
  final int? linkedBillId;
  final String? linkedInvoiceNumber;

  const ServiceAdditionalInfo({
    this.templateId,
    this.templateName,
    this.customFields = const {},
    this.fieldDefinitions = const [],
    this.printServiceItemLabel = false,
    this.linkedBillId,
    this.linkedInvoiceNumber,
  });

  static ServiceAdditionalInfo fromRaw(dynamic raw) {
    if (raw == null) return const ServiceAdditionalInfo();
    if (raw is Map) {
      return fromMap(Map<String, dynamic>.from(raw));
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return const ServiceAdditionalInfo();
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const ServiceAdditionalInfo();
      return fromMap(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const ServiceAdditionalInfo();
    }
  }

  static ServiceAdditionalInfo fromJsonString(String? raw) => fromRaw(raw);

  static ServiceAdditionalInfo fromMap(Map<String, dynamic> map) {
    final custom = map['custom_fields'] ?? map['customFields'];
    final rawFields = map['field_definitions'] ?? map['fieldDefinitions'];
    final List<ServiceFieldModel> parsedFields;
    if (rawFields is List) {
      parsedFields = rawFields
          .whereType<Map>()
          .map((e) => ServiceFieldModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      parsedFields = [];
    }

    return ServiceAdditionalInfo(
      templateId: (map['template_id'] ?? map['templateId'])?.toString(),
      templateName: (map['template_name'] ?? map['templateName'])?.toString(),
      customFields: custom is Map ? Map<String, dynamic>.from(custom) : const {},
      fieldDefinitions: parsedFields,
      printServiceItemLabel: map['print_service_item_label'] == true ||
          map['printServiceItemLabel'] == true,
      linkedBillId: map['linked_bill_id'] is int
          ? map['linked_bill_id'] as int
          : int.tryParse(
              (map['linked_bill_id'] ?? map['linkedBillId'])?.toString() ?? '',
            ),
      linkedInvoiceNumber:
          (map['linked_invoice_number'] ?? map['linkedInvoiceNumber'])
              ?.toString(),
    );
  }

  static List<ServiceFieldModel> resolveFieldDefinitions({
    ServiceTemplateModel? liveTemplate,
    required ServiceAdditionalInfo info,
  }) {
    if (liveTemplate != null && liveTemplate.fields.isNotEmpty) {
      return liveTemplate.fields;
    }
    return info.fieldDefinitions;
  }

  static String displayValue(dynamic value) {
    if (ServiceFieldType.isPatternValue(value)) return 'Pattern';
    if (value is List) {
      return value.map((e) => e.toString()).where((e) => e.isNotEmpty).join(', ');
    }
    final text = value?.toString() ?? '';
    return text;
  }
}
