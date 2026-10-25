// Conditional export: on web this resolves to file_download_web.dart (a real
// browser download); everywhere else to file_download_stub.dart, which has no
// web imports so mobile/desktop builds still compile.
//
// dart.library.js_interop is true for both normal web builds and WebAssembly
// builds (dart.library.html is false for WebAssembly).
export 'file_download_stub.dart' if (dart.library.js_interop) 'file_download_web.dart';