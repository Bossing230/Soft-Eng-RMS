import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/menu.dart';
import 'package:rms/Frontend/repositories/order_repository.dart';
import 'package:rms/Frontend/services/api_services.dart';
import '../../repositories/menu_repository.dart';
import '../../repositories/table_repository.dart';

// ---------------------------------------------------------------------------
// Design tokens, taken from the POS design.
// ---------------------------------------------------------------------------
class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const tan = Color(0xFFD4A574);
  static const tanDeep = Color(0xFFB98A5E);
  static const tanTint = Color(0xFFF0DFCF);
  static const searchFill = Color(0xFFF1EBE4);
  static const fieldFill = Color(0xFFFBF5F0);
  static const pillIdle = Color(0xFFEFE9E0);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
  static const redText = Color(0xFFE53935);
}

String _peso(num v) => '₱${v.toStringAsFixed(2)}';
double _round2(double v) => (v * 100).roundToDouble() / 100;

class CartLine {
  final MenuItem item;
  int quantity;
  CartLine(this.item, this.quantity);
  double get subtotal => item.price * quantity;
}

/// Cashier point-of-sale screen: pick an order type and (for dine-in) a
/// table, browse and search the available menu, build a cart, then place
/// the order and take payment, all on one page.
class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final _menuRepo = MenuRepository();
  final _tableRepo = TableRepository();
  final _orderRepo = OrderRepository();
  final _api = ApiService();
  final _searchController = TextEditingController();
  final _cashReceivedController = TextEditingController();

  List<MenuItem> _menu = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _tables = [];
  final Map<int, CartLine> _cart = {};

  String _orderType = 'dine_in'; // dine_in | takeout | delivery
  int? _selectedCategoryId; // null = All
  int? _selectedTableId;
  String _query = '';
  String _paymentMethod = 'cash'; // cash | card | ewallet

  // Falls back to a sensible default if the rates endpoint isn't available yet
  // (e.g. the backend hasn't been redeployed), so the preview still works.
  double _taxRate = 0.12;
  double _serviceChargeRate = 0.0;

  bool _loading = true;
  bool _placing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cashReceivedController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _menuRepo.getAll(availability: 'available'),
        _menuRepo.getCategories(),
        _tableRepo.getAll(status: 'available'),
      ]);
      // Optional: if this fails (older backend), the defaults above still work.
      try {
        final rates = await _api.get('/config/order-rates');
        _taxRate = double.tryParse('${rates['taxRate']}') ?? _taxRate;
        _serviceChargeRate = double.tryParse('${rates['serviceChargeRate']}') ?? _serviceChargeRate;
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _menu = results[0] as List<MenuItem>;
        _categories = results[1] as List<Map<String, dynamic>>;
        _tables = results[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- menu / filtering ----

  List<MenuItem> get _visibleMenu {
    final q = _query.trim().toLowerCase();
    return _menu.where((item) {
      if (_selectedCategoryId != null && item.categoryId != _selectedCategoryId) return false;
      if (q.isEmpty) return true;
      return item.foodName.toLowerCase().contains(q);
    }).toList();
  }

  // ---- cart ----

  void _addToCart(MenuItem item) {
    setState(() {
      _cart.update(item.menuId, (line) => CartLine(item, line.quantity + 1), ifAbsent: () => CartLine(item, 1));
    });
  }

  void _incrementLine(CartLine line) => setState(() => line.quantity += 1);

  void _decrementLine(CartLine line) {
    setState(() {
      if (line.quantity <= 1) {
        _cart.remove(line.item.menuId);
      } else {
        line.quantity -= 1;
      }
    });
  }

  void _clearCart() {
    if (_cart.isEmpty) return;
    setState(() => _cart.clear());
  }

  double get _subtotal => _cart.values.fold(0.0, (sum, l) => sum + l.subtotal);
  double get _taxAndService => _round2(_subtotal * (_taxRate + _serviceChargeRate));
  double get _total => _round2(_subtotal + _taxAndService);

  // ---- order type / table ----

  void _setOrderType(String type) {
    setState(() {
      _orderType = type;
      if (type != 'dine_in') _selectedTableId = null;
    });
  }

  // ---- place order + pay ----

  Future<void> _placeOrder() async {
    if (_cart.isEmpty || _placing) return;
    if (_orderType == 'dine_in' && _selectedTableId == null) {
      _snack('Choose a table for this dine-in order.');
      return;
    }
    if (_orderType == 'dine_in' && _tables.isEmpty) {
      _snack('No tables are available right now.');
      return;
    }

    double? cashReceived;
    if (_paymentMethod == 'cash') {
      final text = _cashReceivedController.text.trim();
      cashReceived = text.isEmpty ? _total : double.tryParse(text);
      if (cashReceived == null) {
        _snack('Enter a valid cash amount, or leave it blank for the exact total.');
        return;
      }
      if (cashReceived < _total) {
        _snack('Cash received is less than the total (${_peso(_total)}).');
        return;
      }
    }

    setState(() => _placing = true);
    final items = _cart.values.map((l) => {'menuId': l.item.menuId, 'quantity': l.quantity}).toList();

    try {
      final order = await _orderRepo.create(
        orderType: _orderType,
        tableId: _selectedTableId,
        items: items,
      );

      try {
        final body = <String, dynamic>{'orderId': order.orderId, 'method': _paymentMethod};
        if (_paymentMethod == 'cash') body['cashReceived'] = cashReceived;
        if (_paymentMethod == 'card') body['cardToken'] = 'demo-card-token';
        final result = await _api.post('/payments', body: body);
        final payment = Map<String, dynamic>.from(result['payment'] ?? {});
        final checkoutUrl = result['checkoutUrl'];

        if (checkoutUrl != null) {
          _snack('Order #${order.orderId} placed. Customer checkout: $checkoutUrl');
        } else if (payment['payment_status'] == 'paid') {
          final change = payment['change'];
          _snack(change != null && (change as num) > 0
              ? 'Order #${order.orderId} paid. Change due: ${_peso(change)}'
              : 'Order #${order.orderId} placed and paid.');
        } else {
          _snack('Order #${order.orderId} placed. Payment is pending.');
        }
      } on ApiException catch (e) {
        _snack('Order #${order.orderId} was placed, but payment failed: ${e.message}');
      } catch (e) {
        _snack('Order #${order.orderId} was placed, but payment failed: $e');
      }

      setState(() {
        _cart.clear();
        _selectedTableId = null;
        _cashReceivedController.clear();
      });
      _load(); // refreshes available tables and menu
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not place the order: $e');
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40, color: _Ui.muted),
              const SizedBox(height: 12),
              Text("Couldn't load the menu: $_error", textAlign: TextAlign.center, style: const TextStyle(color: _Ui.muted)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final menuArea = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TypeAndTableRow(
          orderType: _orderType,
          onTypeChanged: _setOrderType,
          tables: _tables,
          selectedTableId: _selectedTableId,
          onTableChanged: (id) => setState(() => _selectedTableId = id),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search menu...',
              prefixIcon: const Icon(Icons.search, size: 20, color: _Ui.muted),
              filled: true,
              fillColor: _Ui.searchFill,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.tan)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _CategoryPills(
            categories: _categories,
            selectedId: _selectedCategoryId,
            onSelected: (id) => setState(() => _selectedCategoryId = id),
          ),
        ),
        Expanded(
          child: _visibleMenu.isEmpty
              ? const Center(child: Text('No menu items match.', style: TextStyle(color: _Ui.muted)))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisExtent: 188,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: _visibleMenu.length,
                  itemBuilder: (_, i) => _MenuTile(item: _visibleMenu[i], onTap: () => _addToCart(_visibleMenu[i])),
                ),
        ),
      ],
    );

    final cartPanel = _CartPanel(
      cart: _cart.values.toList(),
      subtotal: _subtotal,
      taxAndService: _taxAndService,
      taxRate: _taxRate + _serviceChargeRate,
      total: _total,
      paymentMethod: _paymentMethod,
      cashReceivedController: _cashReceivedController,
      placing: _placing,
      onIncrement: _incrementLine,
      onDecrement: _decrementLine,
      onClear: _clearCart,
      onPaymentMethodChanged: (m) => setState(() => _paymentMethod = m),
      onPlaceOrder: _placeOrder,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            children: [
              Expanded(flex: 2, child: menuArea),
              const VerticalDivider(width: 1, color: _Ui.border),
              SizedBox(width: 340, child: cartPanel),
            ],
          );
        }
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                labelColor: _Ui.tanDeep,
                unselectedLabelColor: _Ui.muted,
                indicatorColor: _Ui.tanDeep,
                tabs: [
                  const Tab(text: 'Menu'),
                  Tab(text: _cart.isEmpty ? 'Order' : 'Order (${_cart.length})'),
                ],
              ),
              Expanded(child: TabBarView(children: [menuArea, cartPanel])),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Order type pills + table picker
// ---------------------------------------------------------------------------

class _TypeAndTableRow extends StatelessWidget {
  final String orderType;
  final ValueChanged<String> onTypeChanged;
  final List<Map<String, dynamic>> tables;
  final int? selectedTableId;
  final ValueChanged<int?> onTableChanged;
  const _TypeAndTableRow({
    required this.orderType,
    required this.onTypeChanged,
    required this.tables,
    required this.selectedTableId,
    required this.onTableChanged,
  });

  static const _types = {'dine_in': 'Dine-in', 'takeout': 'Takeout', 'delivery': 'Delivery'};

  @override
  Widget build(BuildContext context) {
    final pills = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _types.entries.map((e) {
        final selected = e.key == orderType;
        return Material(
          color: selected ? _Ui.tanDeep : _Ui.pillIdle,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onTypeChanged(e.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Text(
                e.value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : _Ui.muted,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );

    final tableDropdown = _TableDropdown(
      enabled: orderType == 'dine_in',
      tables: tables,
      selectedId: selectedTableId,
      onChanged: onTableChanged,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [tableDropdown, pills],
      ),
    );
  }
}

class _TableDropdown extends StatelessWidget {
  final bool enabled;
  final List<Map<String, dynamic>> tables;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  const _TableDropdown({required this.enabled, required this.tables, required this.selectedId, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: enabled ? _Ui.fieldFill : _Ui.pillIdle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _Ui.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedId,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          hint: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.table_bar_outlined, size: 18, color: enabled ? _Ui.muted : _Ui.muted.withOpacity(0.5)),
              const SizedBox(width: 8),
              Text(
                enabled ? (tables.isEmpty ? 'No tables free' : 'Table') : 'Table',
                style: TextStyle(fontSize: 13, color: enabled ? _Ui.muted : _Ui.muted.withOpacity(0.5)),
              ),
            ],
          ),
          items: tables
              .map((t) => DropdownMenuItem<int>(
                    value: t['table_id'] as int,
                    child: Text('Table ${t['table_number']}', style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category pills
// ---------------------------------------------------------------------------

class _CategoryPills extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final int? selectedId;
  final ValueChanged<int?> onSelected;
  const _CategoryPills({required this.categories, required this.selectedId, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _pill(context, null, 'All'),
          for (final c in categories) ...[
            const SizedBox(width: 8),
            _pill(context, c['category_id'] as int, '${c['category_name']}'),
          ],
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, int? id, String label) {
    final selected = id == selectedId;
    return Material(
      color: selected ? _Ui.tanDeep : _Ui.pillIdle,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onSelected(id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Colors.white : _Ui.muted,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Menu tile
// ---------------------------------------------------------------------------

class _MenuTile extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;
  const _MenuTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: _Ui.border)),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    color: _Ui.tanTint,
                    child: item.image == null || item.image!.isEmpty
                        ? const Center(child: Icon(Icons.restaurant, color: _Ui.tanDeep, size: 28))
                        : Image.network(
                            item.image!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.restaurant, color: _Ui.tanDeep, size: 28)),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.foodName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _Ui.ink),
              ),
              if (item.categoryName != null)
                Text(
                  item.categoryName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _Ui.muted),
                ),
              const SizedBox(height: 2),
              Text(_peso(item.price), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Ui.tanDeep)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cart panel
// ---------------------------------------------------------------------------

class _CartPanel extends StatelessWidget {
  final List<CartLine> cart;
  final double subtotal;
  final double taxAndService;
  final double taxRate;
  final double total;
  final String paymentMethod;
  final TextEditingController cashReceivedController;
  final bool placing;
  final ValueChanged<CartLine> onIncrement;
  final ValueChanged<CartLine> onDecrement;
  final VoidCallback onClear;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onPlaceOrder;
  const _CartPanel({
    required this.cart,
    required this.subtotal,
    required this.taxAndService,
    required this.taxRate,
    required this.total,
    required this.paymentMethod,
    required this.cashReceivedController,
    required this.placing,
    required this.onIncrement,
    required this.onDecrement,
    required this.onClear,
    required this.onPaymentMethodChanged,
    required this.onPlaceOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Text('Current order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: _Ui.ink)),
                const Spacer(),
                if (cart.isNotEmpty)
                  TextButton(
                    onPressed: onClear,
                    style: TextButton.styleFrom(foregroundColor: _Ui.redText, padding: EdgeInsets.zero),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: _Ui.border),
          Expanded(
            child: cart.isEmpty
                ? const Center(child: Text('Tap a menu item to add it.', style: TextStyle(color: _Ui.muted)))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: cart.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _CartRow(line: cart[i], onIncrement: onIncrement, onDecrement: onDecrement),
                  ),
          ),
          const Divider(height: 1, color: _Ui.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TotalsRow(label: 'Subtotal', value: subtotal),
                const SizedBox(height: 4),
                _TotalsRow(label: 'Tax & service (${(taxRate * 100).toStringAsFixed(0)}%)', value: taxAndService),
                const SizedBox(height: 8),
                _TotalsRow(label: 'Total', value: total, emphasize: true),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: paymentMethod,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _Ui.fieldFill,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(value: 'ewallet', child: Text('E-wallet')),
                  ],
                  onChanged: (v) {
                    if (v != null) onPaymentMethodChanged(v);
                  },
                ),
                if (paymentMethod == 'cash') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: cashReceivedController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: 'Cash received (leave blank for exact ${_peso(total)})',
                      filled: true,
                      fillColor: _Ui.fieldFill,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ],
                if (paymentMethod == 'ewallet') ...[
                  const SizedBox(height: 8),
                  const Text(
                    'The customer will be sent a GCash/Maya checkout link.',
                    style: TextStyle(fontSize: 11, color: _Ui.muted),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: cart.isEmpty || placing ? null : onPlaceOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _Ui.tanDeep,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _Ui.tanDeep.withOpacity(0.4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: placing
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Place order', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  final CartLine line;
  final ValueChanged<CartLine> onIncrement;
  final ValueChanged<CartLine> onDecrement;
  const _CartRow({required this.line, required this.onIncrement, required this.onDecrement});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepperButton(icon: Icons.remove, onTap: () => onDecrement(line)),
        SizedBox(
          width: 24,
          child: Text('${line.quantity}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        _StepperButton(icon: Icons.add, onTap: () => onIncrement(line)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            line.item.foodName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: _Ui.ink),
          ),
        ),
        Text(_peso(line.subtotal), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Ui.ink)),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Ui.pillIdle,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(width: 26, height: 26, child: Icon(icon, size: 15, color: _Ui.tanDeep)),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final String label;
  final double value;
  final bool emphasize;
  const _TotalsRow({required this.label, required this.value, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _Ui.ink)
        : const TextStyle(fontSize: 13, color: _Ui.muted);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(_peso(value), style: style),
      ],
    );
  }
}