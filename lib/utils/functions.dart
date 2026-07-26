import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'constants.dart';

Future<void> logErrorToFile(String error, [StackTrace? stackTrace]) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/error_log.txt');
    final timestamp = DateTime.now().toIso8601String();
    final logEntry =
        '\n[$timestamp] $error${stackTrace != null ? '\n$stackTrace' : ''}\n';
    await file.writeAsString(logEntry, mode: FileMode.append);
  } catch (e) {
    // Optionally print to console if file logging fails
    print('Failed to log error: $e');
  }
}

void showSnackbar(BuildContext context, String message, {Color? backgroundColor}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor ?? Colors.grey[800],
    ),
  );
}

Color generateColorFromCode(String code) {
  if (code.isEmpty) return Colors.grey;
  
  // Generate a consistent color from the code string
  int hash = 0;
  for (int i = 0; i < code.length; i++) {
    hash = code.codeUnitAt(i) + ((hash << 5) - hash);
  }
  
  // Generate RGB values
  int r = (hash & 0xFF0000) >> 16;
  int g = (hash & 0x00FF00) >> 8;
  int b = hash & 0x0000FF;
  
  // Ensure colors are not too dark or too light
  r = (r + 100) % 200 + 55;
  g = (g + 100) % 200 + 55;
  b = (b + 100) % 200 + 55;
  
  return Color.fromRGBO(r, g, b, 1.0);
}

String receiptSizeFromRemote(dynamic raw) {
  final value = raw?.toString().trim() ?? '';
  if (RECEIPT_SIZE_OPTIONS.contains(value)) return value;
  return kDefaultReceiptSize;
}

Map<String, String> normalizedMaskedJsonFromValue(dynamic raw) {
  final out = <String, String>{};
  for (int i = 0; i < 10; i++) {
    final key = '$i';
    if (raw is Map) {
      final dynamic v = raw[key] ?? raw[i];
      var s = v?.toString() ?? key;
      if (s.isEmpty) s = key;
      out[key] = s.substring(0, 1);
    } else {
      out[key] = key;
    }
  }
  return out;
}

bool boolSettingFromRemote(dynamic raw, bool fallback) {
  if (raw is bool) return raw;
  if (raw == null) return fallback;
  final value = raw.toString().trim().toLowerCase();
  if (value == 'true' || value == '1') return true;
  if (value == 'false' || value == '0') return false;
  return fallback;
}

String roundOffFrequencyFromRemote(dynamic value) {
  final s = value?.toString().trim().toLowerCase() ?? '';
  if (s == kRoundOffFrequencyDecimal || s == 'rupee' || s == 'paise') {
    return kRoundOffFrequencyDecimal;
  }
  if (s == kRoundOffFrequencyNearest5 || s == 'nearest_5' || s == '5') {
    return kRoundOffFrequencyNearest5;
  }
  if (s == kRoundOffFrequencyNearest10 || s == 'nearest_10' || s == '10') {
    return kRoundOffFrequencyNearest10;
  }
  return kRoundOffFrequencyNearest10;
}

int labelPrinterDpiFromRemote(dynamic raw) {
  if (raw == null) return 203;
  final n = raw is num
      ? raw.round()
      : (int.tryParse(raw.toString().trim()) ?? 203);
  return n >= 250 ? 300 : 203;
}

String jewelTagPrintDirectionFromRemote(dynamic raw) {
  final value = raw?.toString().trim().toLowerCase() ?? '';
  if (JEWEL_TAG_PRINT_DIRECTION_OPTIONS.contains(value)) return value;
  return 'left';
}

void normalizeLabelTemplateGlobals() {
  if (!LABEL_TEMPLATE_DEFAULT_ENABLED && !LABEL_TEMPLATE_CUSTOM_ENABLED) {
    LABEL_TEMPLATE_DEFAULT_ENABLED = true;
  }
}

void applyLabelTemplateSettingsFromRemote(Map<String, dynamic> data) {
  if (data.containsKey('labelTemplateDefault') ||
      data.containsKey('labelTemplateCustom')) {
    LABEL_TEMPLATE_DEFAULT_ENABLED =
        boolSettingFromRemote(data['labelTemplateDefault'], true);
    LABEL_TEMPLATE_CUSTOM_ENABLED =
        boolSettingFromRemote(data['labelTemplateCustom'], false);
    normalizeLabelTemplateGlobals();
    return;
  }
  final legacy = data['labelTemplate']?.toString().trim().toLowerCase() ?? '';
  if (legacy == 'custom') {
    LABEL_TEMPLATE_DEFAULT_ENABLED = false;
    LABEL_TEMPLATE_CUSTOM_ENABLED = true;
  } else if (legacy.isNotEmpty) {
    LABEL_TEMPLATE_DEFAULT_ENABLED = true;
    LABEL_TEMPLATE_CUSTOM_ENABLED = false;
  }
  normalizeLabelTemplateGlobals();
}

bool disableBillTypeConfirmationFromRemoteSettings(Map<String, dynamic>? data) {
  if (data == null) return false;
  if (data['disableBillTypeConfirmation'] is bool) {
    return data['disableBillTypeConfirmation'] as bool;
  }
  if (data['billTypeConfirmation'] is bool) {
    return !(data['billTypeConfirmation'] as bool);
  }
  return false;
}
