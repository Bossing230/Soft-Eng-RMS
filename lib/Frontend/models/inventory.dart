class InventoryItem {
  final int inventoryId;
  final String ingredientName;
  final double quantity;
  final String unit;
  final double minimumStock;
  final String status;

  InventoryItem({
    required this.inventoryId,
    required this.ingredientName,
    required this.quantity,
    required this.unit,
    required this.minimumStock,
    required this.status,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      inventoryId: int.parse(json['inventory_id'].toString()),
      ingredientName: json['ingredient_name'] ?? '',
      quantity: double.parse(json['quantity'].toString()),
      unit: json['unit'] ?? '',
      minimumStock: double.parse(json['minimum_stock'].toString()),
      status: json['status'] ?? 'ok',
    );
  }
}