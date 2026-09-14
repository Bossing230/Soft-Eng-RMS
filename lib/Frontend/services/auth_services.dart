import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import 'package:rms/Frontend/services/api_services.dart';

class AuthService {
  final ApiService _api = ApiService();
  final SessionManager _session = SessionManager();

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
}