import 'package:rms/Frontend/services/api_services.dart';
import '../models/order.dart';

class OrderRepository {
  final ApiService _api = ApiService();

  Future<List<RmsOrder>> getAll({String? status, String? date}) async {
    final data = await _api.get('/orders', query: {
      if (status != null) 'status': status,
      if (date != null) 'date': date,
    });
    return (data as List).map((e) => RmsOrder.fromJson(e)).toList();
  }

  /// The Orders page: today's orders plus anything still open, newest first.
  /// Each order says which statuses the signed-in user may move it to.
  Future<List<RmsOrder>> getBoard() async {
    final data = await _api.get('/orders/board');
    return (data as List).map((e) => RmsOrder.fromJson(e)).toList();
  }

  Future<List<RmsOrder>> getKitchenQueue() async {
    final data = await _api.get('/orders/kitchen-queue');
    return (data as List).map((e) => RmsOrder.fromJson(e)).toList();
  }

  Future<RmsOrder> getOne(int orderId) async {
    final data = await _api.get('/orders/$orderId');
    return RmsOrder.fromJson(data);
  }

  /// [orderType] is 'dine_in', 'takeout' or 'delivery'. [tableNumber] only
  /// applies to dine-in orders ("3" and "T3" both find table T3).
  Future<RmsOrder> create({
    int? tableId,
    String? tableNumber,
    String orderType = 'dine_in',
    required List<Map<String, dynamic>> items,
    double discount = 0,
  }) async {
    final data = await _api.post('/orders', body: {
      'tableId': tableId,
      if (tableNumber != null && tableNumber.trim().isNotEmpty) 'tableNumber': tableNumber.trim(),
      'orderType': orderType,
      'items': items, // [{ menuId, quantity }]
      'discount': discount,
    });
    return RmsOrder.fromJson(data);
  }

  Future<RmsOrder> updateStatus(int orderId, String status) async {
    final data = await _api.patch('/orders/$orderId/status', body: {'status': status});
    return RmsOrder.fromJson(data);
  }

  Future<void> cancel(int orderId) => _api.post('/orders/$orderId/cancel');
}