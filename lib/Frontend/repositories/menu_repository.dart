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

  /// [ingredients] is the dish's recipe: [{ 'inventoryId': 3, 'quantity': 30 }, ...],
  /// each quantity in that inventory item's own unit, for ONE serving.
  /// Leave it out (or empty) for a dish whose stock should not be tracked.
  Future<MenuItem> create({
    required int categoryId,
    required String foodName,
    required String description,
    required double price,
    String? image,
    String? station,
    List<Map<String, dynamic>>? ingredients,
  }) async {
    final data = await _api.post('/menu', body: {
      'categoryId': categoryId,
      'foodName': foodName,
      'description': description,
      'price': price,
      if (image != null) 'image': image,
      if (station != null) 'station': station,
      if (ingredients != null && ingredients.isNotEmpty) 'ingredients': ingredients,
    });
    return MenuItem.fromJson(data);
  }

  /// Updates a dish's details (not its recipe or availability, which have
  /// their own calls). Expects the backend route `PUT /menu/:id`.
  Future<void> update(
    int menuId, {
    required int categoryId,
    required String foodName,
    required String description,
    required double price,
    String? image,
    String? station,
  }) async {
    await _api.put('/menu/$menuId', body: {
      'categoryId': categoryId,
      'foodName': foodName,
      'description': description,
      'price': price,
      if (image != null) 'image': image,
      if (station != null) 'station': station,
    });
  }

  Future<void> setAvailability(int menuId, bool available) {
    return _api.patch('/menu/$menuId/availability', body: {
      'availability': available ? 'available' : 'unavailable',
    });
  }

  /// Which kitchen station this dish is cooked at. One of: Grill, Pasta,
  /// Salad, Desserts, Drinks.
  Future<MenuItem> setStation(int menuId, String station) async {
    final data = await _api.post('/menu/$menuId/station', body: {'station': station});
    return MenuItem.fromJson(data);
  }

  Future<void> delete(int menuId) => _api.delete('/menu/$menuId');

  // ---- Recipes ----

  /// Inventory items a recipe can use, each with inventory_id, ingredient_name,
  /// unit, unit_cost (per unit) and quantity (current stock).
  Future<List<Map<String, dynamic>>> getRecipeIngredientOptions() async {
    final data = await _api.get('/recipes/ingredients');
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// A dish's recipe with cost_per_serving and servings_available.
  Future<Map<String, dynamic>> getRecipe(int menuId) async {
    final data = await _api.get('/recipes/$menuId');
    return Map<String, dynamic>.from(data);
  }

  /// Replaces a dish's whole recipe. An empty list removes it.
  Future<Map<String, dynamic>> saveRecipe(int menuId, List<Map<String, dynamic>> ingredients) async {
    final data = await _api.put('/recipes/$menuId', body: {'ingredients': ingredients});
    return Map<String, dynamic>.from(data);
  }
}