import 'package:rms/Frontend/models/menu.dart';
import 'package:rms/Frontend/services/api_services.dart';

class MenuRepository {
  final ApiService _api = ApiService();

  Future<List<MenuItem>> getAll({String? search, String? availability}) async {
    final data = await _api.get('/menu', query: {
      if (search != null) 'search': search,
      if (availability != null) 'availability': availability,
    });
    return (data as List).map((e) => MenuItem.fromJson(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final data = await _api.get('/menu/categories');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createCategory(String categoryName) async {
    final data = await _api.post('/menu/categories', body: {
      'categoryName': categoryName,
    });
    return Map<String, dynamic>.from(data);
  }

  /// Uploads an image and returns its relative URL (e.g. "/uploads/xyz.jpg").
  /// Pass this straight into `create(...)`'s `image` argument.
  Future<String> uploadImage({required List<int> bytes, required String filename}) async {
    final data = await _api.uploadFile('/menu/upload-image', bytes: bytes, filename: filename);
    return data['imageUrl'] as String;
  }

  Future<MenuItem> create({
    required int categoryId,
    required String foodName,
    required String description,
    required double price,
    String? image,
  }) async {
    final data = await _api.post('/menu', body: {
      'categoryId': categoryId,
      'foodName': foodName,
      'description': description,
      'price': price,
      if (image != null) 'image': image,
    });
    return MenuItem.fromJson(data);
  }

  Future<void> setAvailability(int menuId, bool available) {
    return _api.patch('/menu/$menuId/availability', body: {
      'availability': available ? 'available' : 'unavailable',
    });
  }

  Future<void> delete(int menuId) => _api.delete('/menu/$menuId');
}