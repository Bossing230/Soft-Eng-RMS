import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Mobile / desktop version: saves the file to the app's temp folder, then
/// opens the system share sheet so the person can save or open it.
///
/// Keeps the same synchronous signature as the web version, so no other file
/// needs to change. The save and share run in the background.
bool downloadBytes(Uint8List bytes, {required String filename, required String mimeType}) {
  _saveAndShare(bytes, filename: filename, mimeType: mimeType);
  return true;
}

Future<void> _saveAndShare(
  Uint8List bytes, {
  required String filename,
  required String mimeType,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}${Platform.pathSeparator}$safeName');
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: safeName)],
        subject: safeName,
      ),
    );
  } catch (e) {
    debugPrint('Download failed: $e');
  }
}