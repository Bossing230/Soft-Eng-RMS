import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rms/Frontend/repositories/order_repository.dart';
import 'package:rms/Frontend/services/socket_services.dart';
import '../../models/order.dart';

/// Kitchen Staff queue: shows confirmed/preparing orders and lets the
/// chef move each one forward (Confirmed -> Preparing -> Ready).
/// Also listens live over Socket.IO so new orders pop in without
/// a manual refresh.
class KitchenQueuePage extends StatefulWidget {
  const KitchenQueuePage({super.key});

  @override
  State<KitchenQueuePage> createState() => _KitchenQueuePageState();
}

class _KitchenQueuePageState extends State<KitchenQueuePage> {
  final _repo = OrderRepository();
  final _socket = SocketService();
  List<RmsOrder> _orders = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _socket.connect((_) => _load()); // any notification event triggers a refresh
    // Fallback polling in case the socket connection drops.
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _socket.disconnect();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _repo.getKitchenQueue();
      if (mounted) setState(() { _orders = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _advance(RmsOrder order) async {
    final next = order.orderStatus == 'confirmed' ? 'preparing' : 'ready';
    await _repo.updateStatus(order.orderId, next);
    _load();
  }

  Color _statusColor(String status) => status == 'preparing' ? Colors.orange : Colors.blue;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_orders.isEmpty) {
      return const Center(child: Text('No orders in the queue right now.', style: TextStyle(color: Colors.grey)));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 320, mainAxisExtent: 220, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: _orders.length,
        itemBuilder: (_, i) {
          final order = _orders[i];
          return Card(
            color: _statusColor(order.orderStatus).withOpacity(0.06),
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
                        label: Text(order.orderStatus.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10)),
                        backgroundColor: _statusColor(order.orderStatus),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (order.tableNumber != null) Text('Table: ${order.tableNumber}'),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(
                      children: order.items.map((i) => Text('${i.quantity}x ${i.foodName}')).toList(),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _advance(order),
                    child: Text(order.orderStatus == 'confirmed' ? 'Start Preparing' : 'Mark Ready'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}