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
  //
  // None of these three calls are auto-retried: a retry after a timeout would
  // create a second code / email, or count a wrong code twice against the
  // 5-attempt limit. A timeout is shown to the person instead.

  /// Sends a fresh 6-digit code to [email], if it belongs to an account.
  /// Returns the masked email it was sent to (e.g. "ju**@example.com").
  /// Throws [ApiException] (404 no account, 429 too soon, 502 email failed),
  /// or a TimeoutException if the server doesn't answer in 40 seconds
  /// (long enough to cover a free-tier host waking up).
  Future<String> requestPasswordResetCode(String email) async {
    final data = await _api.post(
      '/auth/forgot-password/request',
      body: {'email': email},
      retry: false,
      timeout: const Duration(seconds: 40),
    );
    return data['maskedEmail'] as String;
  }

  /// Checks [code] for [email]. On success returns a short-lived reset
  /// token to pass to [resetPasswordWithCode]. Throws [ApiException]
  /// (401 wrong code, 410 expired, 429 too many tries) otherwise.
  Future<String> verifyPasswordResetCode(String email, String code) async {
    final data = await _api.post(
      '/auth/forgot-password/verify',
      body: {'email': email, 'code': code},
      retry: false,
      timeout: const Duration(seconds: 25),
    );
    return data['resetToken'] as String;
  }

  /// Sets the new password using the token from [verifyPasswordResetCode],
  /// and signs the person straight in. Returns a confirmation number.
  Future<String> resetPasswordWithCode(String resetToken, String newPassword) async {
    final data = await _api.post(
      '/auth/forgot-password/reset',
      body: {'resetToken': resetToken, 'newPassword': newPassword},
      retry: false,
      timeout: const Duration(seconds: 25),
    );
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