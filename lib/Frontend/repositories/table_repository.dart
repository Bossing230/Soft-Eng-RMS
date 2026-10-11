import 'package:rms/Frontend/services/api_services.dart';

/// Kept deliberately simple (raw maps, not a model class): the project already
/// has its own `DiningTable` model (models/dining_table.dart) for plain
/// listings; this repository additionally powers the Tables board, which
/// needs a couple of fields (location, customer_name) that model doesn't have.
class TableRepository {
  final ApiService _api = ApiService();

  Future<List<Map<String, dynamic>>> getAll({String? status}) async {
    final data = await _api.get('/tables', query: {if (status != null) 'status': status});
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Every table with its current status, capacity, location, and — for an
  /// occupied table with a seated reservation today — the guest's name.
  Future<List<Map<String, dynamic>>> getBoard() async {
    final data = await _api.get('/tables/board');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> create({
    required String tableNumber,
    required int capacity,
    String location = 'indoor',
  }) async {
    final data = await _api.post('/tables', body: {
      'tableNumber': tableNumber,
      'capacity': capacity,
      'location': location,
    });
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> update(int tableId, {String? tableNumber, int? capacity, String? location}) async {
    final data = await _api.put('/tables/$tableId', body: {
      if (tableNumber != null) 'tableNumber': tableNumber,
      if (capacity != null) 'capacity': capacity,
      if (location != null) 'location': location,
    });
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> setStatus(int tableId, String status) async {
    final data = await _api.patch('/tables/$tableId/status', body: {'status': status});
    return Map<String, dynamic>.from(data);
  }
}