import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import '../core/constants/app_constants.dart';
/// Thin wrapper around http calls to the backend REST API.
/// Every repository goes through this single class so headers,
/// error handling, and the base URL stay in one place.
class ApiService {
  final _session = SessionManager();

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('${AppConstants.apiBaseUrl}$path');
    if (query == null) return base;
    return base.replace(queryParameters: query.map((k, v) => MapEntry(k, v.toString())));
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_session.token != null) 'Authorization': 'Bearer ${_session.token}',
      };

  dynamic _handle(http.Response res) {
    final body = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }
    final message = body is Map && body['error'] != null ? body['error'] : 'Request failed (${res.statusCode})';
    throw ApiException(message, res.statusCode);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final res = await http.get(_uri(path, query), headers: _headers);
    return _handle(res);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final res = await http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {}));
    return _handle(res);
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    final res = await http.put(_uri(path), headers: _headers, body: jsonEncode(body ?? {}));
    return _handle(res);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    final res = await http.patch(_uri(path), headers: _headers, body: jsonEncode(body ?? {}));
    return _handle(res);
  }

  Future<dynamic> delete(String path) async {
    final res = await http.delete(_uri(path), headers: _headers);
    return _handle(res);
  }

  // Maps a filename's extension to a proper MIME type, since the backend
  // checks this (via multer's fileFilter) to confirm it's really an image.
  MediaType _mediaTypeFor(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'gif':
        return MediaType('image', 'gif');
      case 'jpg':
      case 'jpeg':
      default:
        return MediaType('image', 'jpeg');
    }
  }

  /// Uploads a single image file as multipart/form-data. Works on both
  /// web and mobile since it takes raw bytes rather than a dart:io File.
  Future<dynamic> uploadFile(String path, {required List<int> bytes, required String filename, String field = 'image'}) async {
    final request = http.MultipartRequest('POST', _uri(path));
    if (_session.token != null) {
      request.headers['Authorization'] = 'Bearer ${_session.token}';
    }
    request.files.add(http.MultipartFile.fromBytes(
      field,
      bytes,
      filename: filename,
      contentType: _mediaTypeFor(filename),
    ));

    final streamedResponse = await request.send();
    final res = await http.Response.fromStream(streamedResponse);
    return _handle(res);
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}