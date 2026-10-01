import 'dart:typed_data';

Future<void> downloadBytes(Uint8List bytes, String filename) async {
  throw UnsupportedError(
    'File download is only supported on web in this admin app.',
  );
}
