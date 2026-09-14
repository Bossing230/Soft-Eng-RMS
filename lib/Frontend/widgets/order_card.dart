import 'package:flutter/material.dart';
import '../models/order.dart';

class OrderCard extends StatelessWidget {
  final RmsOrder order;
  final List<Widget> actions;

  const OrderCard({super.key, required this.order, this.actions = const []});

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.grey;
      case 'confirmed':
        return Colors.blue;
      case 'preparing':
        return Colors.orange;
      case 'ready':
        return Colors.green;
      case 'completed':
        return Colors.teal;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order #${order.orderId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Chip(
                  label: Text(order.orderStatus.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11)),
                  backgroundColor: _statusColor(order.orderStatus),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (order.tableNumber != null) Text('Table: ${order.tableNumber}'),
            Text('Total: ₱${order.totalAmount.toStringAsFixed(2)}'),
            if (order.items.isNotEmpty) ...[
              const Divider(),
              ...order.items.map((i) => Text('${i.quantity}x ${i.foodName}')),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}