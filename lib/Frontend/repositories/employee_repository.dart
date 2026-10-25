import 'package:rms/Frontend/services/api_services.dart';
import '../models/employee.dart';

class EmployeeRepository {
  final ApiService _api = ApiService();

  Future<List<Employee>> getAll({String? role, String? status}) async {
    final data = await _api.get('/employees', query: {
      if (role != null) 'role': role,
      if (status != null) 'status': status,
    });
    return (data as List).map((e) => Employee.fromJson(e)).toList();
  }

  Future<String> uploadPhoto({required List<int> bytes, required String filename}) async {
    final data = await _api.uploadFile('/menu/upload-image', bytes: bytes, filename: filename);
    return data['imageUrl'] as String;
  }

  /// Emails a 6-digit code to [email] so the admin can confirm the address
  /// is real before creating the account. Returns the masked address.
  /// Throws [ApiException]: 409 email already in use, 429 too soon (check
  /// `e.body['retryAfterSeconds']`), 502 email could not be sent. Not
  /// auto-retried, so a timeout can't send two emails.
  Future<String> requestEmailCode(String email) async {
    final data = await _api.post(
      '/employees/email-code/request',
      body: {'email': email},
      retry: false,
      timeout: const Duration(seconds: 40),
    );
    return data['maskedEmail'] as String;
  }

  /// Checks the code. On success returns a short-lived token that proves
  /// this exact email was verified; pass it to [create].
  /// Throws [ApiException]: 401 wrong code, 410 expired, 429 too many tries.
  Future<String> verifyEmailCode(String email, String code) async {
    final data = await _api.post(
      '/employees/email-code/verify',
      body: {'email': email, 'code': code},
      retry: false,
      timeout: const Duration(seconds: 25),
    );
    return data['emailToken'] as String;
  }

  Future<Employee> create({
    required String name,
    required String username,
    required String email,
    required String emailToken,
    required String password,
    required String role,
    String? profileImage,
  }) async {
    final data = await _api.post('/employees', body: {
      'name': name,
      'username': username,
      'email': email,
      'emailToken': emailToken,
      'password': password,
      'role': role,
      if (profileImage != null) 'profileImage': profileImage,
    });
    return Employee.fromJson(data);
  }

  Future<void> setStatus(int employeeId, bool active) {
    return _api.patch('/employees/$employeeId/status', body: {'status': active ? 'active' : 'inactive'});
  }

  Future<void> resetPassword(int employeeId, String newPassword) {
    return _api.post('/employees/$employeeId/reset-password', body: {'newPassword': newPassword});
  }
}