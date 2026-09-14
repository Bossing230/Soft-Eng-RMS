import 'package:flutter/material.dart';
import 'package:rms/Frontend/repositories/order_respository.dart';
import '../../models/order.dart';
import '../../widgets/order_card.dart';

class OrderManagementPage extends StatefulWidget {
  final bool canForceCancel;
  const OrderManagementPage({super.key, this.canForceCancel = false});

  @override
  State<OrderManagementPage> createState() => _OrderManagementPageState();
}

class _OrderManagementPageState extends State<OrderManagementPage> {
  final _repo = OrderRepository();
  List<RmsOrder> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _repo.getAll();
    setState(() {
      _orders = data;
      _loading = false;
    });
  }

  // Maps the current status to the single next status a Cashier/Manager may set.
  String? _nextStatus(String status) {
    switch (status) {
      case 'pending':
        return 'confirmed';
      case 'ready':
        return 'completed';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        itemBuilder: (_, i) {
          final order = _orders[i];
          final next = _nextStatus(order.orderStatus);
          final actions = <Widget>[];

          if (next != null) {
            actions.add(ElevatedButton(
              onPressed: () async { await _repo.updateStatus(order.orderId, next); _load(); },
              child: Text(next == 'confirmed' ? 'Send to Kitchen' : 'Mark Completed'),
            ));
          }
          if (widget.canForceCancel && order.orderStatus != 'completed' && order.orderStatus != 'cancelled') {
            actions.add(TextButton(
              onPressed: () async { await _repo.cancel(order.orderId); _load(); },
              child: const Text('Cancel', style: TextStyle(color: Colors.red)),
            ));
          }

          return OrderCard(order: order, actions: actions);
        },
      ),
    );
  }
}