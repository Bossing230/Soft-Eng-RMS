import 'package:rms/Frontend/services/api_services.dart';

/// Kept deliberately simple (raw maps, not a model class): the project already
/// has its own `DiningTable` model (models/dining_table.dart) whose exact
/// shape wasn't available here, so this avoids clashing with it. Each map has
/// table_id, table_number, capacity and status.
class TableRepository {
  final ApiService _api = ApiService();

  Future<List<Map<String, dynamic>>> getAll({String? status}) async {
    final data = await _api.get('/tables', query: {if (status != null) 'status': status});
    return (data as List).cast<Map<String, dynamic>>();
  }
}