import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import 'package:rms/Frontend/services/api_services.dart';

class AuthService {
  final ApiService _api = ApiService();
  final SessionManager _session = SessionManager();

  /// Throws [ApiException] on failure. For a 423 (locked) response, check
  /// `e.body` for `justLocked`, `lockedUntil`, and `lockoutMinutes`; for a
  /// 401, check `e.body['attemptsRemaining']`.
  Future<void> login(String username, String password) async {
    final data = await _api.post('/auth/login', body: {'username': username, 'password': password});
    final user = data['user'];
    await _session.saveSession(
      token: data['token'],
      employeeId: user['employeeId'],
      name: user['name'],
      username: user['username'],
      role: user['role'],
      email: user['email'],
      profileImage: user['profileImage'],
    );
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Even if the network call fails, clear the local session.
    }
    await _session.clear();
  }

  Future<void> changePassword(String currentPassword, String newPassword) {
    return _api.post('/auth/change-password', body: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  // --- Forgot password (email + 6-digit code) ------------------------------

  /// Sends a fresh 6-digit code to the email already on file for [username].
  /// Returns the masked email it was sent to (e.g. "ju**@example.com").
  /// Throws [ApiException] with statusCode 429 if called again too soon —
  /// check `e.body['retryAfterSeconds']`.
  Future<String> requestPasswordResetCode(String username) async {
    final data = await _api.post('/auth/forgot-password/request', body: {'username': username});
    return data['maskedEmail'] as String;
  }

  /// Checks [code] for [username]. On success returns a short-lived reset
  /// token to pass to [resetPasswordWithCode]. Throws [ApiException]
  /// (401 wrong code, 410 expired, 429 too many tries) otherwise.
  Future<String> verifyPasswordResetCode(String username, String code) async {
    final data = await _api.post('/auth/forgot-password/verify', body: {'username': username, 'code': code});
    return data['resetToken'] as String;
  }

  /// Sets the new password using the token from [verifyPasswordResetCode],
  /// and signs the person straight in (saves the session) so the app can go
  /// directly to their dashboard. Returns a confirmation number to show them.
  Future<String> resetPasswordWithCode(String resetToken, String newPassword) async {
    final data = await _api.post('/auth/forgot-password/reset', body: {
      'resetToken': resetToken,
      'newPassword': newPassword,
    });
    final user = data['user'];
    await _session.saveSession(
      token: data['token'],
      employeeId: user['employeeId'],
      name: user['name'],
      username: user['username'],
      role: user['role'],
      email: user['email'],
      profileImage: user['profileImage'],
    );
    return data['confirmationNumber'] as String;
  }
}