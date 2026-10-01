import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'download_bytes_stub.dart'
    if (dart.library.html) 'download_bytes_web.dart' as impl;

Future<void> downloadBytes(Uint8List bytes, String filename) {
  return impl.downloadBytes(bytes, filename);
}

/// Convenience for plain-text fallbacks.
Future<void> downloadText(String text, String filename) {
  return downloadBytes(Uint8List.fromList(utf8.encode(text)), filename);
}

void debugDownloadInfo(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
