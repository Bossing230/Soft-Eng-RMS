import 'package:rms/Frontend/models/notification.dart';
import 'package:rms/Frontend/services/api_services.dart';
class NotificationRepository {
  final ApiService _api = ApiService();

  Future<List<NotificationItem>> getAll({bool unreadOnly = false}) async {
    final data = await _api.get('/notifications', query: {'unreadOnly': unreadOnly});
    return (data as List).map((e) => NotificationItem.fromJson(e)).toList();
  }

  Future<void> markRead(int notificationId) => _api.patch('/notifications/$notificationId/read');

  Future<void> markAllRead() => _api.patch('/notifications/read-all');
}