import 'package:intl/intl.dart';
import 'package:rms/Frontend/models/activity_log.dart';
import 'package:rms/Frontend/services/api_services.dart';

class ActivityLogRepository {
  final ApiService _api = ApiService();
  static final _day = DateFormat('yyyy-MM-dd');

  /// One page of the log, newest first. [from] and [to] are whole days, both
  /// included. [type] is a kind from [getKinds]; [role] only has an effect for
  /// administrators and managers (everyone else only ever sees their own).
  Future<ActivityLogPageResult> getLogs({
    required DateTime from,
    required DateTime to,
    String? type,
    String? role,
    String? search,
    int page = 1,
    int limit = 10,
  }) async {
    final data = await _api.get('/activity-logs', query: {
      'from': _day.format(from),
      'to': _day.format(to),
      if (type != null) 'type': type,
      if (role != null) 'role': role,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'page': page,
      'limit': limit,
    });
    return ActivityLogPageResult.fromJson(Map<String, dynamic>.from(data));
  }

  /// The kinds of activity that exist, for the "All Activities" dropdown.
  Future<List<String>> getKinds() async {
    final data = await _api.get('/activity-logs/kinds');
    return (data as List).map((e) => '$e').toList();
  }
}