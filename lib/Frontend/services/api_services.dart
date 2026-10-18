import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import '../core/constants/app_constants.dart';

/// Thin wrapper around http calls to the backend REST API.
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
    throw ApiException(message, res.statusCode, body is Map ? Map<String, dynamic>.from(body) : null);
  }

  /// Retries a request up to 2 extra times if it fails with a network
  /// error or a 502/503/504 — the exact symptoms of a free-tier host
  /// (like Render) still waking up from sleep. Each retry waits a bit
  /// longer, giving the server time to finish booting.
  Future<http.Response> _withRetry(Future<http.Response> Function() request) async {
    const delays = [Duration(seconds: 3), Duration(seconds: 6)];
    for (var attempt = 0; ; attempt++) {
      try {
        final res = await request().timeout(const Duration(seconds: 20));
        final isGatewayError = res.statusCode == 502 || res.statusCode == 503 || res.statusCode == 504;
        if (isGatewayError && attempt < delays.length) {
          await Future.delayed(delays[attempt]);
          continue;
        }
        return res;
      } catch (e) {
        if (attempt < delays.length) {
          await Future.delayed(delays[attempt]);
          continue;
        }
        rethrow;
      }
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final res = await _withRetry(() => http.get(_uri(path, query), headers: _headers));
    return _handle(res);
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final res = await _withRetry(() => http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));
    return _handle(res);
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    final res = await _withRetry(() => http.put(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));
    return _handle(res);
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    final res = await _withRetry(() => http.patch(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));
    return _handle(res);
  }

  Future<dynamic> delete(String path) async {
    final res = await _withRetry(() => http.delete(_uri(path), headers: _headers));
    return _handle(res);
  }

  /// For endpoints that return a binary file (PDF, Excel) instead of JSON —
  /// used for "Download Report" style buttons. Unlike the other methods this
  /// never runs the body through jsonDecode, since a successful response here
  /// isn't JSON; an error response (4xx/5xx) still is, so that path is
  /// decoded as usual to surface a real error message.
  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? query}) async {
    final res = await _withRetry(() => http.get(_uri(path, query), headers: _headers));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }
    String message = 'Request failed (${res.statusCode})';
    try {
      final body = res.body.isNotEmpty ? jsonDecode(res.body) : null;
      if (body is Map && body['error'] != null) message = body['error'];
    } catch (_) {
      // Error body wasn't JSON either; keep the generic message.
    }
    throw ApiException(message, res.statusCode);
  }

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

  Future<dynamic> uploadFile(String path, {required List<int> bytes, required String filename, String field = 'image'}) async {
    final res = await _withRetry(() async {
      final request = http.MultipartRequest('POST', _uri(path));
      if (_session.token != null) {
        request.headers['Authorization'] = 'Bearer ${_session.token}';
      }
      request.files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename, contentType: _mediaTypeFor(filename)));
      final streamedResponse = await request.send();
      return http.Response.fromStream(streamedResponse);
    });
    return _handle(res);
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  /// The full decoded error response, when the server sent extra fields
  /// beyond `error` (e.g. login lockout details: lockedUntil, lockoutMinutes,
  /// justLocked, attemptsRemaining). Null if the body wasn't a JSON object.
  final Map<String, dynamic>? body;

  ApiException(this.message, this.statusCode, [this.body]);

  @override
  String toString() => message;
}