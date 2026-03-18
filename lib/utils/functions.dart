import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
