import 'dart:typed_data';

/// Returns true if the download was handed off to the platform (web only, for
/// now). Callers should show their own message when this returns false.
bool downloadBytes(Uint8List bytes, {required String filename, required String mimeType}) {
  return false;
}