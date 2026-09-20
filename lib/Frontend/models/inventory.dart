import 'dart:math' as math;

class InventoryItem {
  final int inventoryId;
  final String ingredientName;
  final double quantity;
  final String unit;
  final double minimumStock;
  final String status; // 'ok' | 'low' | 'out'
  final double maxStock;
  final String category;

  InventoryItem({
    required this.inventoryId,
    required this.ingredientName,
    required this.quantity,
    required this.unit,
    required this.minimumStock,
    required this.status,
    this.maxStock = 0,
    this.category = '',
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      inventoryId: int.parse(json['inventory_id'].toString()),
      ingredientName: json['ingredient_name'] ?? '',
      quantity: double.parse(json['quantity'].toString()),
      unit: json['unit'] ?? '',
      minimumStock: double.parse(json['minimum_stock'].toString()),
      status: json['status'] ?? 'ok',
      maxStock: double.tryParse('${json['max_stock'] ?? 0}') ?? 0,
      category: (json['category'] ?? '').toString(),
    );
  }

  bool get isLow => status == 'low';
  bool get isOut => status == 'out';

  /// Low or out of stock.
  bool get needsRestock => status != 'ok';

  /// What counts as 100% full. Falls back to the current stock if no max was set.
  double get capacity => maxStock > 0 ? maxStock : math.max(quantity, minimumStock);

  /// 0.0 to 1.0
  double get fraction => capacity <= 0 ? 0.0 : (quantity / capacity).clamp(0.0, 1.0).toDouble();

  int get percent => (fraction * 100).round();
}

/// One line of an item's stock history.
class InventoryTransaction {
  final String type; // 'delivery' | 'usage' | 'adjustment'
  final double quantity; // signed: positive added stock, negative removed it
  final String employeeName;
  final String time; // restaurant-local, 'YYYY-MM-DD HH:MM:SS'

  InventoryTransaction({
    required this.type,
    required this.quantity,
    required this.employeeName,
    required this.time,
  });

  factory InventoryTransaction.fromJson(Map<String, dynamic> json) {
    return InventoryTransaction(
      type: (json['transaction_type'] ?? '').toString(),
      quantity: double.tryParse('${json['quantity']}') ?? 0,
      employeeName: (json['employee_name'] ?? '').toString(),
      time: (json['local_time'] ?? json['transaction_date'] ?? '').toString(),
    );
  }
}