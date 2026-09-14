import 'package:rms/Frontend/services/api_services.dart';

class DashboardRepository {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> getSummary() async {
    final data = await _api.get('/reports/dashboard');
    return Map<String, dynamic>.from(data);
  }

  /// Daily order-count/total-sales rows between two dates (inclusive),
  /// used to draw the revenue bar chart.
  Future<List<Map<String, dynamic>>> getSalesTrend({required String start, required String end}) async {
    final data = await _api.get('/reports/sales', query: {'start': start, 'end': end});
    return (data['rows'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getBestSellers({required String start, required String end, int limit = 5}) async {
    final data = await _api.get('/reports/best-sellers', query: {'start': start, 'end': end, 'limit': limit});
    return (data['rows'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getStaffPerformance({required String date}) async {
    final data = await _api.get('/reports/staff-performance', query: {'date': date});
    return (data as List).cast<Map<String, dynamic>>();
  }
}