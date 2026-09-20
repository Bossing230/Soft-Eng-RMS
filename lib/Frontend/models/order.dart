class OrderItem {
  final int orderItemId;
  final int menuId;
  final String foodName;
  final int quantity;
  final double unitPrice;
  final double subtotal;

  OrderItem({
    required this.orderItemId,
    required this.menuId,
    required this.foodName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      orderItemId: int.parse(json['order_item_id'].toString()),
      menuId: int.parse(json['menu_id'].toString()),
      foodName: json['food_name'] ?? '',
      quantity: int.parse(json['quantity'].toString()),
      unitPrice: double.parse(json['unit_price'].toString()),
      subtotal: double.parse(json['subtotal'].toString()),
    );
  }
}

class RmsOrder {
  final int orderId;
  final String? tableNumber;
  final String employeeName;
  final DateTime orderDate;
  final String orderStatus; // pending | confirmed | preparing | ready | served | completed | cancelled
  final double subtotal;
  final double discount;
  final double tax;
  final double totalAmount;
  final String paymentStatus;
  final List<OrderItem> items;

  /// dine_in | takeout | delivery
  final String orderType;

  /// cash | card | ewallet | online, or null when no payment was started yet.
  final String? paymentMethod;

  /// How old the order is, worked out by the server (null when not provided).
  final int? minutesAgo;

  /// The statuses the signed-in user may move this order to (Orders page only).
  final List<String> allowedNext;

  RmsOrder({
    required this.orderId,
    this.tableNumber,
    required this.employeeName,
    required this.orderDate,
    required this.orderStatus,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.totalAmount,
    required this.paymentStatus,
    this.items = const [],
    this.orderType = 'dine_in',
    this.paymentMethod,
    this.minutesAgo,
    this.allowedNext = const [],
  });

  factory RmsOrder.fromJson(Map<String, dynamic> json) {
    return RmsOrder(
      orderId: int.parse(json['order_id'].toString()),
      tableNumber: json['table_number'],
      employeeName: json['employee_name'] ?? '',
      orderDate: DateTime.tryParse(json['order_date'] ?? '') ?? DateTime.now(),
      orderStatus: json['order_status'] ?? 'pending',
      subtotal: double.parse((json['subtotal'] ?? 0).toString()),
      discount: double.parse((json['discount'] ?? 0).toString()),
      tax: double.parse((json['tax'] ?? 0).toString()),
      totalAmount: double.parse((json['total_amount'] ?? 0).toString()),
      paymentStatus: json['payment_status'] ?? 'pending',
      items: (json['items'] as List<dynamic>? ?? []).map((i) => OrderItem.fromJson(i)).toList(),
      orderType: json['order_type'] ?? 'dine_in',
      paymentMethod: json['payment_method'],
      minutesAgo: json['minutes_ago'] == null ? null : int.tryParse(json['minutes_ago'].toString()),
      allowedNext: (json['allowed_next'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
    );
  }
}