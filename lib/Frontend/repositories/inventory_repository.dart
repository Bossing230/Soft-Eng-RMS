import 'package:rms/Frontend/models/inventory.dart';
import 'package:rms/Frontend/services/api_services.dart';

class InventoryRepository {
  final ApiService _api = ApiService();

  Future<List<InventoryItem>> getAll({String? status}) async {
    final data = await _api.get('/inventory', query: {if (status != null) 'status': status});
    return (data as List).map((e) => InventoryItem.fromJson(e)).toList();
  }

  Future<List<InventoryItem>> getLowStock() async {
    final data = await _api.get('/inventory/low-stock');
    return (data as List).map((e) => InventoryItem.fromJson(e)).toList();
  }

  Future<InventoryItem> create({
    required String ingredientName,
    required double quantity,
    required String unit,
    required double minimumStock,
  }) async {
    final data = await _api.post('/inventory', body: {
      'ingredientName': ingredientName, 'quantity': quantity, 'unit': unit, 'minimumStock': minimumStock,
    });
    return InventoryItem.fromJson(data);
  }

  Future<void> adjustStock(int inventoryId, double quantity, String type) {
    return _api.post('/inventory/$inventoryId/adjust', body: {'quantity': quantity, 'type': type});
  }
}