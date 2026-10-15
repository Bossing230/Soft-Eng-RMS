class MenuItem {
  final int menuId;
  final int categoryId;
  final String foodName;
  final String description;
  final double price;
  final String? image;
  final String availability;
  final String? categoryName;

  /// Which kitchen station cooks this dish: Grill, Pasta, Salad, Desserts or
  /// Drinks. Null only for an item created before stations existed and not
  /// yet backfilled.
  final String? station;

  MenuItem({
    required this.menuId,
    required this.categoryId,
    required this.foodName,
    required this.description,
    required this.price,
    this.image,
    required this.availability,
    this.categoryName,
    this.station,
  });

  bool get isAvailable => availability == 'available';

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      menuId: int.parse(json['menu_id'].toString()),
      categoryId: int.parse(json['category_id'].toString()),
      foodName: json['food_name'] ?? '',
      description: json['description'] ?? '',
      price: double.parse(json['price'].toString()),
      image: json['image'],
      availability: json['availability'] ?? 'available',
      categoryName: json['category_name'],
      station: json['station'],
    );
  }
}