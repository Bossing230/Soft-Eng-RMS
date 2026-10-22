import 'dart:math' as math;

class InventoryItem {
  final int inventoryId;
  final String ingredientName;
  final double quantity;
  final String unit;
  final double minimumStock;
  final String status; // 'ok' | 'low' | 'out' — the stored 3-state used for alerting
  final double maxStock;
  final String category;

  /// Finer-grained than [status] for display: 'ok' | 'low' | 'critical' | 'out'.
  /// Computed by the server, never stored.
  final String severity;

  /// 'YYYY-MM-DD', or null if no expiry date has been set for this item.
  final String? expiryDate;

  /// Cost per unit. 0 if nobody has set a cost for this item yet.
  final double unitCost;

  /// When this item's details were last changed, as the server sends it
  /// (local to the restaurant's time zone already).
  final String? lastUpdated;

  InventoryItem({
    required this.inventoryId,
    required this.ingredientName,
    required this.quantity,
    required this.unit,
    required this.minimumStock,
    required this.status,
    this.maxStock = 0,
    this.category = '',
    this.severity = 'ok',
    this.expiryDate,
    this.unitCost = 0,
    this.lastUpdated,
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
      severity: (json['severity'] ?? json['status'] ?? 'ok').toString(),
      expiryDate: json['expiry_date'],
      unitCost: double.tryParse('${json['unit_cost'] ?? 0}') ?? 0,
      lastUpdated: json['updated_at']?.toString(),
    );
  }

  bool get isLow => status == 'low';
  bool get isOut => status == 'out';
  bool get isCritical => severity == 'critical';

  /// Low, critical, or out of stock.
  bool get needsRestock => status != 'ok';

  /// What counts as 100% full. Falls back to the current stock if no max was set.
  double get capacity => maxStock > 0 ? maxStock : math.max(quantity, minimumStock);

  /// 0.0 to 1.0
  double get fraction => capacity <= 0 ? 0.0 : (quantity / capacity).clamp(0.0, 1.0).toDouble();

  int get percent => (fraction * 100).round();

  /// What this item's current stock is worth, using its own unit cost.
  double get stockValue => quantity * unitCost;

  bool get hasExpiryDate => expiryDate != null && expiryDate!.isNotEmpty;

  /// Days from today until expiry (negative if already past). Null if no
  /// expiry date is set.
  int? get daysUntilExpiry {
    if (!hasExpiryDate) return null;
    final date = DateTime.tryParse(expiryDate!);
    if (date == null) return null;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return date.difference(todayDate).inDays;
  }

  bool get isExpired => (daysUntilExpiry ?? 1) < 0;
  bool get isExpiringSoon => hasExpiryDate && (daysUntilExpiry ?? 99) >= 0 && (daysUntilExpiry ?? 99) <= 7;
}

/// One line of an item's stock history.
class InventoryTransaction {
  final String type; // 'delivery' | 'usage' | 'adjustment' | 'return'
  final double quantity; // signed: positive added stock, negative removed it
  final String employeeName;
  final String time; // restaurant-local, 'YYYY-MM-DD HH:MM:SS'
  final int? orderId; // set when an order caused this change

  InventoryTransaction({
    required this.type,
    required this.quantity,
    required this.employeeName,
    required this.time,
    this.orderId,
  });

  factory InventoryTransaction.fromJson(Map<String, dynamic> json) {
    return InventoryTransaction(
      type: (json['transaction_type'] ?? '').toString(),
      quantity: double.tryParse('${json['quantity']}') ?? 0,
      employeeName: (json['employee_name'] ?? '').toString(),
      time: (json['local_time'] ?? json['transaction_date'] ?? '').toString(),
      orderId: int.tryParse('${json['order_id'] ?? ''}'),
    );
  }
}

/// One line of the "Recent Activity" feed: a stock change on some item,
/// across the whole inventory (not scoped to one item like [InventoryTransaction]).
class InventoryActivity {
  final String type; // 'delivery' | 'usage' | 'adjustment' | 'return'
  final double quantity;
  final String ingredientName;
  final String time;
  final int? orderId;

  InventoryActivity({
    required this.type,
    required this.quantity,
    required this.ingredientName,
    required this.time,
    this.orderId,
  });

  factory InventoryActivity.fromJson(Map<String, dynamic> json) {
    return InventoryActivity(
      type: (json['transaction_type'] ?? '').toString(),
      quantity: double.tryParse('${json['quantity']}') ?? 0,
      ingredientName: (json['ingredient_name'] ?? '').toString(),
      time: (json['local_time'] ?? '').toString(),
      orderId: int.tryParse('${json['order_id'] ?? ''}'),
    );
  }
}

class InventoryCategoryCount {
  final String category;
  final int count;
  InventoryCategoryCount({required this.category, required this.count});

  factory InventoryCategoryCount.fromJson(Map<String, dynamic> json) {
    return InventoryCategoryCount(
      category: (json['category'] ?? 'Uncategorized').toString(),
      count: int.tryParse('${json['count']}') ?? 0,
    );
  }
}

/// Everything the Inventory overview panel needs in one response.
class InventoryOverview {
  final List<InventoryCategoryCount> categories;
  final int totalItems;
  final int outCount;
  final int criticalCount;
  final int lowCount;
  final int okCount;
  final int expiringCount;
  final double totalValue;
  final int pricedCount;
  final InventoryItem? actionNeeded;
  final List<InventoryActivity> recentActivity;

  InventoryOverview({
    required this.categories,
    required this.totalItems,
    required this.outCount,
    required this.criticalCount,
    required this.lowCount,
    required this.okCount,
    required this.expiringCount,
    required this.totalValue,
    required this.pricedCount,
    required this.actionNeeded,
    required this.recentActivity,
  });

  factory InventoryOverview.fromJson(Map<String, dynamic> json) {
    final totals = Map<String, dynamic>.from(json['totals'] ?? {});
    num asNum(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);
    return InventoryOverview(
      categories: ((json['categories'] as List?) ?? [])
          .map((e) => InventoryCategoryCount.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      totalItems: asNum(totals['total_items']).toInt(),
      outCount: asNum(totals['out_count']).toInt(),
      criticalCount: asNum(totals['critical_count']).toInt(),
      lowCount: asNum(totals['low_count']).toInt(),
      okCount: asNum(totals['ok_count']).toInt(),
      expiringCount: asNum(totals['expiring_count']).toInt(),
      totalValue: asNum(totals['total_value']).toDouble(),
      pricedCount: asNum(totals['priced_count']).toInt(),
      actionNeeded: json['actionNeeded'] == null ? null : InventoryItem.fromJson(Map<String, dynamic>.from(json['actionNeeded'])),
      recentActivity: ((json['recentActivity'] as List?) ?? [])
          .map((e) => InventoryActivity.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}