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

  /// The low-stock line is worked out by the server (30% of max stock).
  Future<InventoryItem> create({
    required String ingredientName,
    required double quantity,
    required String unit,
    double? maxStock,
    double? minimumStock,
    String category = '',
  }) async {
    final data = await _api.post('/inventory', body: {
      'ingredientName': ingredientName,
      'quantity': quantity,
      'unit': unit,
      'category': category,
      if (maxStock != null) 'maxStock': maxStock,
      if (minimumStock != null) 'minimumStock': minimumStock,
    });
    return InventoryItem.fromJson(data);
  }

  /// Edits name, unit, category and max stock. Use [adjustStock] to change the quantity.
  Future<InventoryItem> update(
    int inventoryId, {
    required String ingredientName,
    required String unit,
    required double maxStock,
    String category = '',
  }) async {
    final data = await _api.put('/inventory/$inventoryId', body: {
      'ingredientName': ingredientName,
      'unit': unit,
      'maxStock': maxStock,
      'category': category,
    });
    return InventoryItem.fromJson(data);
  }

  /// [type] is 'delivery' (+), 'usage' (-) or 'adjustment' (signed correction).
  /// Returns the item as it is after the change.
  Future<InventoryItem> adjustStock(int inventoryId, double quantity, String type) async {
    final data = await _api.post('/inventory/$inventoryId/adjust', body: {'quantity': quantity, 'type': type});
    return InventoryItem.fromJson(data);
  }

  Future<List<InventoryTransaction>> history(int inventoryId) async {
    final data = await _api.get('/inventory/$inventoryId/history');
    return (data as List).map((e) => InventoryTransaction.fromJson(e)).toList();
  }

  /// Records a delivery for each item (inventoryId -> quantity received), all or nothing.
  Future<void> restock(Map<int, double> quantities) {
    return _api.post('/inventory/restock', body: {
      'items': quantities.entries.map((e) => {'inventoryId': e.key, 'quantity': e.value}).toList(),
    });
  }
}