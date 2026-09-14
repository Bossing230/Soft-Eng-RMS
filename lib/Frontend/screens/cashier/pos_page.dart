import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/menu.dart';
import 'package:rms/Frontend/repositories/order_respository.dart';
import 'package:rms/Frontend/services/api_services.dart';
import '../../repositories/menu_repository.dart';
import 'checkout_page.dart';

class CartLine {
  final MenuItem item;
  int quantity;
  CartLine(this.item, this.quantity);
  double get subtotal => item.price * quantity;
}

/// Cashier point-of-sale screen: browse the available menu, build a
/// cart, then create the order (which the kitchen will see immediately).
class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final _menuRepo = MenuRepository();
  final _orderRepo = OrderRepository();
  final _tableNumberCtrl = TextEditingController();

  List<MenuItem> _menu = [];
  final Map<int, CartLine> _cart = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _menuRepo.getAll(availability: 'available');
      setState(() => _menu = items);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  void _addToCart(MenuItem item) {
    setState(() {
      _cart.update(item.menuId, (line) => CartLine(item, line.quantity + 1), ifAbsent: () => CartLine(item, 1));
    });
  }

  void _removeFromCart(MenuItem item) {
    setState(() {
      final line = _cart[item.menuId];
      if (line == null) return;
      if (line.quantity <= 1) {
        _cart.remove(item.menuId);
      } else {
        line.quantity -= 1;
      }
    });
  }

  double get _cartTotal => _cart.values.fold(0.0, (sum, l) => sum + l.subtotal);

  Future<void> _submitOrder() async {
    if (_cart.isEmpty) return;
    try {
      final order = await _orderRepo.create(
        tableId: null, // table linking can be added once a table picker is wired to `tables` endpoint
        items: _cart.values.map((l) => {'menuId': l.item.menuId, 'quantity': l.quantity}).toList(),
      );
      setState(() => _cart.clear());
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => CheckoutPage(order: order)));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Failed to load menu: $_error'));

    final isWide = MediaQuery.of(context).size.width >= 800;
    final menuGrid = GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 130, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: _menu.length,
      itemBuilder: (_, i) {
        final item = _menu[i];
        return Card(
          child: InkWell(
            onTap: () => _addToCart(item),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(item.foodName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('₱${item.price.toStringAsFixed(2)}', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                ],
              ),
            ),
          ),
        );
      },
    );

    final cartPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _tableNumberCtrl,
            decoration: const InputDecoration(labelText: 'Table (optional — walk-in if blank)'),
          ),
        ),
        Expanded(
          child: _cart.isEmpty
              ? const Center(child: Text('Cart is empty. Tap a menu item to add it.'))
              : ListView(
                  children: _cart.values.map((line) {
                    return ListTile(
                      title: Text(line.item.foodName),
                      subtitle: Text('₱${line.item.price.toStringAsFixed(2)} x ${line.quantity}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _removeFromCart(line.item)),
                          Text('${line.quantity}'),
                          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _addToCart(line.item)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subtotal', style: TextStyle(fontSize: 16)),
                  Text('₱${_cartTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Tax & service charge are applied at checkout', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _cart.isEmpty ? null : _submitOrder,
                child: const Text('Send Order to Kitchen'),
              ),
            ],
          ),
        ),
      ],
    );

    if (isWide) {
      return Row(
        children: [
          Expanded(flex: 2, child: menuGrid),
          const VerticalDivider(width: 1),
          Expanded(flex: 1, child: cartPanel),
        ],
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: 'Menu'), Tab(text: 'Cart')]),
          Expanded(child: TabBarView(children: [menuGrid, cartPanel])),
        ],
      ),
    );
  }
}