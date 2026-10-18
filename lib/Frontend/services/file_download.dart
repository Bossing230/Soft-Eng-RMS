// Conditional export: on web this resolves to file_download_web.dart (a real
// browser download via dart:html); everywhere else to file_download_stub.dart,
// which has no dart:html import so mobile/desktop builds still compile.
export 'file_download_stub.dart' if (dart.library.html) 'file_download_web.dart';