import 'package:rms/Frontend/services/api_services.dart';

class DashboardRepository {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> getSummary() async {
    final data = await _api.get('/reports/dashboard');
    return Map<String, dynamic>.from(data);
  }

  /// Everything the Administrator overview shows, for Daily, Weekly and
  /// Monthly at once (so switching between them needs no new request):
  /// revenue and chart buckets and top sellers per period, open orders, low
  /// stock, available tables, recent orders and today's staff activity.
  Future<Map<String, dynamic>> getAdminOverview() async {
    final data = await _api.get('/reports/admin-overview');
    return Map<String, dynamic>.from(data);
  }

  /// Everything the manager dashboard shows, in one request: today's numbers,
  /// staff counts, the 7-day trend, top sellers, staff activity and alerts.
  Future<Map<String, dynamic>> getManagerOverview() async {
    final data = await _api.get('/reports/manager-overview');
    return Map<String, dynamic>.from(data);
  }

  /// Everything the Reports page shows for one period ('daily', 'weekly' or
  /// 'monthly'): summary numbers, revenue/order buckets and top sellers.
  Future<Map<String, dynamic>> getReportsAnalytics({required String period}) async {
    final data = await _api.get('/reports/analytics', query: {'period': period});
    return Map<String, dynamic>.from(data);
  }

  /// What the cashier's Summary tab shows: their own sales today, pending
  /// orders system-wide, available tables, today's average order value, and
  /// a handful of recent orders.
  Future<Map<String, dynamic>> getCashierSummary() async {
    final data = await _api.get('/reports/cashier-summary');
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