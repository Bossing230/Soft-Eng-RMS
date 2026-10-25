import 'package:intl/intl.dart';
import 'package:rms/Frontend/models/inventory.dart';
import 'package:rms/Frontend/services/api_services.dart';
import 'package:rms/Frontend/services/file_download.dart';

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

  /// Stats, category breakdown, the single most urgent item, and recent
  /// activity across the whole inventory — for the overview panel.
  Future<InventoryOverview> getOverview() async {
    final data = await _api.get('/inventory/overview');
    return InventoryOverview.fromJson(Map<String, dynamic>.from(data));
  }

  /// Uploads a photo and returns its link. Pass it as `image` to
  /// [create], [update] or [setImage].
  Future<String> uploadImage({required List<int> bytes, required String filename}) async {
    final data = await _api.uploadFile('/inventory/upload-image', bytes: bytes, filename: filename);
    return data['imageUrl'] as String;
  }

  /// The low-stock line is worked out by the server (30% of max stock).
  /// [expiryDate] is 'YYYY-MM-DD'; leave both optional fields out for an
  /// item with no known expiry or cost.
  Future<InventoryItem> create({
    required String ingredientName,
    required double quantity,
    required String unit,
    double? maxStock,
    double? minimumStock,
    String category = '',
    String? expiryDate,
    double? unitCost,
    String? image,
  }) async {
    final data = await _api.post('/inventory', body: {
      'ingredientName': ingredientName,
      'quantity': quantity,
      'unit': unit,
      'category': category,
      if (maxStock != null) 'maxStock': maxStock,
      if (minimumStock != null) 'minimumStock': minimumStock,
      if (expiryDate != null) 'expiryDate': expiryDate,
      if (unitCost != null) 'unitCost': unitCost,
      if (image != null && image.isNotEmpty) 'image': image,
    });
    return InventoryItem.fromJson(data);
  }

  /// Edits name, unit, category, max stock, expiry date, unit cost and photo.
  /// Use [adjustStock] to change the quantity. Pass an empty string for
  /// [expiryDate] to clear a previously set date. For [image]: leave it null
  /// to keep the current photo, pass a link to replace it, or pass an empty
  /// string to remove it.
  Future<InventoryItem> update(
    int inventoryId, {
    required String ingredientName,
    required String unit,
    required double maxStock,
    String category = '',
    String? expiryDate,
    double? unitCost,
    String? image,
  }) async {
    final data = await _api.put('/inventory/$inventoryId', body: {
      'ingredientName': ingredientName,
      'unit': unit,
      'maxStock': maxStock,
      'category': category,
      'expiryDate': (expiryDate == null || expiryDate.isEmpty) ? null : expiryDate,
      if (unitCost != null) 'unitCost': unitCost,
      if (image != null) 'image': image,
    });
    return InventoryItem.fromJson(data);
  }

  /// Changes only the photo of one item. An empty [image] removes it.
  Future<InventoryItem> setImage(int inventoryId, String image) async {
    final data = await _api.put('/inventory/$inventoryId/image', body: {'image': image});
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

  /// Downloads the inventory report.
  ///   [format]   'pdf', 'excel' or 'csv'
  ///   [filter]   'all', 'low' (low, critical and out of stock) or 'expiring'
  ///   [category] only items in this category (use 'Uncategorized' for none)
  ///   [search]   only items whose name or category contains this text
  /// Returns true if the browser download started (web only, for now) —
  /// false means the caller should tell the person this isn't supported on
  /// their platform yet.
  Future<bool> downloadReport({
    required String format,
    String filter = 'all',
    String? category,
    String? search,
  }) async {
    final bytes = await _api.getBytes('/inventory/report', query: {
      'format': format,
      'filter': filter,
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.isNotEmpty) 'search': search,
    });

    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final extension = format == 'excel' ? 'xlsx' : format;
    const mimeTypes = {
      'pdf': 'application/pdf',
      'excel': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv': 'text/csv',
    };
    return downloadBytes(
      bytes,
      filename: 'inventory-report-$stamp.$extension',
      mimeType: mimeTypes[format] ?? 'application/octet-stream',
    );
  }

  /// Kept so older callers still work: the full report as a PDF.
  Future<bool> downloadReportPdf() => downloadReport(format: 'pdf');
}