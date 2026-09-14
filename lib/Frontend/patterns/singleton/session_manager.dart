import 'package:shared_preferences/shared_preferences.dart';

/// Singleton Pattern — holds the current auth token/user in memory
/// and mirrors it to SharedPreferences so the session survives restarts.
class SessionManager {
  SessionManager._internal();
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;

  String? token;
  int? employeeId;
  String? name;
  String? username;
  String? email;
  String? role;
  String? profileImage;

  bool get isLoggedIn => token != null;

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    employeeId = prefs.getInt('employeeId');
    name = prefs.getString('name');
    username = prefs.getString('username');
    email = prefs.getString('email');
    role = prefs.getString('role');
    profileImage = prefs.getString('profileImage');
  }

  Future<void> saveSession({
    required String token,
    required int employeeId,
    required String name,
    required String username,
    required String role,
    String? email,
    String? profileImage,
  }) async {
    this.token = token;
    this.employeeId = employeeId;
    this.name = name;
    this.username = username;
    this.role = role;
    this.email = email;
    this.profileImage = profileImage;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setInt('employeeId', employeeId);
    await prefs.setString('name', name);
    await prefs.setString('username', username);
    await prefs.setString('role', role);
    if (email != null) await prefs.setString('email', email);
    if (profileImage != null) await prefs.setString('profileImage', profileImage);
  }

  Future<void> clear() async {
    token = null;
    employeeId = null;
    name = null;
    username = null;
    email = null;
    role = null;
    profileImage = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}