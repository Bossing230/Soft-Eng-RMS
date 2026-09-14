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

  Future<Employee> create({
    required String name,
    required String username,
    required String email,
    required String password,
    required String role,
    String? profileImage,
  }) async {
    final data = await _api.post('/employees', body: {
      'name': name,
      'username': username,
      'email': email,
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