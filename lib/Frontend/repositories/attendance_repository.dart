import 'package:rms/Frontend/services/api_services.dart';

/// Each call returns the employee's new status:
/// 'off', 'on_duty' or 'on_break'.
class AttendanceRepository {
  final ApiService _api = ApiService();

  Future<String> getStatus() async {
    final data = await _api.get('/attendance/me');
    return '${data['status']}';
  }

  Future<String> clockIn() => _post('/attendance/clock-in');
  Future<String> clockOut() => _post('/attendance/clock-out');
  Future<String> startBreak() => _post('/attendance/break/start');
  Future<String> endBreak() => _post('/attendance/break/end');

  Future<String> _post(String path) async {
    final data = await _api.post(path);
    return '${data['status']}';
  }
}