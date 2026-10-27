import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rms/Frontend/repositories/order_repository.dart';
import 'package:rms/Frontend/services/socket_services.dart';

// ---------------------------------------------------------------------------
// Design tokens, taken from the Kitchen Orders design.
// ---------------------------------------------------------------------------
class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const tanDeep = Color(0xFFB98A5E);
  static const tanTint = Color(0xFFF0DFCF);
  static const pillIdle = Color(0xFFEFE9E0);
  static const panelBg = Color(0xFFFAF6F1);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
  static const green = Color(0xFF4CAF50);
  static const greenText = Color(0xFF2E7D32);
  static const redText = Color(0xFFD32F2F);
}

num _asNum(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);
List<Map<String, dynamic>> _asList(dynamic v) =>
    ((v as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

/// The station an item belongs to (an item with no station falls back to Grill).
String _itemStation(Map<String, dynamic> item) {
  final s = '${item['station'] ?? ''}'.trim().toLowerCase();
  return s.isEmpty ? 'grill' : s;
}

/// Only the items of [order] that belong to [stationKey].
List<Map<String, dynamic>> _itemsFor(Map<String, dynamic> order, String stationKey) =>
    _asList(order['items']).where((i) => _itemStation(i) == stationKey).toList();

// Stations this app understands — must match Backend/constants/stations.js.
const _stationIcons = {
  'grill': Icons.local_fire_department_outlined,
  'pasta': Icons.ramen_dining_outlined,
  'salad': Icons.eco_outlined,
  'desserts': Icons.icecream_outlined,
  'drinks': Icons.local_cafe_outlined,
  'counter': Icons.storefront_outlined,
};

// Order status -> the Cooking/Ready/Serving/Delivered track, and its color.
const _trackStages = ['preparing', 'ready', 'served', 'completed'];
const _trackLabels = {'preparing': 'Cooking', 'ready': 'Ready', 'served': 'Serving', 'completed': 'Delivered'};
const _trackIcons = {
  'preparing': Icons.local_fire_department,
  'ready': Icons.check_circle_outline,
  'served': Icons.person_outline,
  'completed': Icons.inventory_2_outlined,
};

class _StatusStyle {
  final Color bg;
  final Color fg;
  const _StatusStyle(this.bg, this.fg);
}

_StatusStyle _cardStatusStyle(String status) {
  switch (status) {
    case 'confirmed':
      return const _StatusStyle(Color(0xFFFFF4D6), Color(0xFFB36B00));
    case 'preparing':
      return const _StatusStyle(Color(0xFFE3F2FD), Color(0xFF1E88E5));
    case 'ready':
      return const _StatusStyle(Color(0xFFE8F5E9), _Ui.greenText);
    case 'served':
      return const _StatusStyle(Color(0xFFE0F2F1), Color(0xFF00796B));
    case 'completed':
      return const _StatusStyle(Color(0xFFF3E5F5), Color(0xFF8E24AA));
    default:
      return const _StatusStyle(_Ui.pillIdle, _Ui.muted);
  }
}

String _cardStatusLabel(String status) {
  switch (status) {
    case 'confirmed':
      return 'Queued';
    default:
      return _trackLabels[status] ?? status;
  }
}

String _typeLabel(String type) {
  switch (type) {
    case 'takeout':
      return 'Takeout';
    case 'delivery':
      return 'Delivery';
    default:
      return 'Dine-in';
  }
}

String _elapsedLabel(int minutes) {
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '${minutes}m';
  if (minutes < 1440) {
    final m = minutes % 60;
    return m == 0 ? '${minutes ~/ 60}h' : '${minutes ~/ 60}h ${m}m';
  }
  final h = (minutes % 1440) ~/ 60;
  return h == 0 ? '${minutes ~/ 1440}d' : '${minutes ~/ 1440}d ${h}h';
}

String _agoLabel(int minutes) => minutes < 1 ? 'just now' : '${_elapsedLabel(minutes)} ago';

String _money(num v) => '₱${v.toStringAsFixed(2)}';

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Kitchen Orders board. The "All Orders" tab shows every active order as a
/// single combined card (listing all of its items, each tagged with its
/// station). Selecting a station tab shows only the orders that have items
/// for that station, and each card lists only that station's items.
///
/// Kitchen staff can start cooking and mark an order ready; moving it on to
/// served/completed is the cashier's job (see the backend's TRANSITIONS
/// table), so those later stages show on the status track but aren't tappable
/// here. Status is per order, not per station.
class KitchenQueuePage extends StatefulWidget {
  const KitchenQueuePage({super.key});

  @override
  State<KitchenQueuePage> createState() => _KitchenQueuePageState();
}

class _KitchenQueuePageState extends State<KitchenQueuePage> {
  final _repo = OrderRepository();
  final _socket = SocketService();
  Timer? _pollTimer;

  List<Map<String, dynamic>> _stations = [];
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic> _performance = {};
  bool _loading = true;
  String? _error;

  String _selectedStation = 'all';
  int? _selectedOrderId;
  final Set<int> _busy = {};

  /// Bumped on every setState so the mobile bottom sheet (which lives outside
  /// this page's widget tree) rebuilds with the latest order and busy state.
  final _tick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _load();
    _socket.connect((_) => _load(showSpinner: false)); // any notification event triggers a refresh
    // Fallback polling in case the socket connection drops.
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load(showSpinner: false));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _socket.disconnect();
    _tick.dispose();
    super.dispose();
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _tick.value++;
  }

  Map<String, dynamic>? _orderById(int id) {
    for (final o in _orders) {
      if (o['order_id'] == id) return o;
    }
    return null;
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _repo.getKitchenBoard();
      if (!mounted) return;
      setState(() {
        _stations = _asList(data['stations']);
        _orders = _asList(data['orders']);
        _performance = Map<String, dynamic>.from(data['performance'] ?? {});
        _loading = false;
        _error = null;
        // Keep the selected order only if it's still on the board.
        if (_selectedOrderId != null && !_orders.any((o) => o['order_id'] == _selectedOrderId)) {
          _selectedOrderId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_orders.isEmpty) _error = '$e';
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Orders shown for the selected tab: every order for "All Orders", or every
  /// order that has at least one item for the selected station.
  List<Map<String, dynamic>> get _visibleOrders {
    if (_selectedStation == 'all') return _orders;
    return _orders.where((o) => _itemsFor(o, _selectedStation).isNotEmpty).toList();
  }

  /// How many open orders have at least one item for this station.
  int _stationCount(String key) => _orders
      .where((o) => o['order_status'] != 'completed' && _itemsFor(o, key).isNotEmpty)
      .length;

  Future<void> _advance(Map<String, dynamic> order, String next) async {
    final orderId = order['order_id'] as int;
    setState(() => _busy.add(orderId));
    try {
      await _repo.updateStatus(orderId, next);
      await _load(showSpinner: false);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy.remove(orderId));
    }
  }

  void _selectOrder(int orderId) {
    final wide = MediaQuery.of(context).size.width >= 1100;
    if (wide) {
      setState(() => _selectedOrderId = orderId);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _Ui.panelBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        // Looks the order up again on every update, so the sheet shows the
        // spinner and the new status right after Start Preparing / Mark as Ready.
        builder: (context, scrollController) => ValueListenableBuilder<int>(
          valueListenable: _tick,
          builder: (context, _, __) {
            final order = _orderById(orderId);
            if (order == null) {
              return const Center(
                child: Text('This order is no longer on the board.', style: TextStyle(color: _Ui.muted)),
              );
            }
            return _OrderDetailPanel(
              order: order,
              busy: _busy.contains(orderId),
              scrollController: scrollController,
              onAdvance: (next) => _advance(order, next),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40, color: _Ui.muted),
              const SizedBox(height: 12),
              const Text("Couldn't load the kitchen board", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _Ui.muted)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final wide = MediaQuery.of(context).size.width >= 1100;
    final selectedOrder = _selectedOrderId == null
        ? null
        : _orders.cast<Map<String, dynamic>?>().firstWhere((o) => o?['order_id'] == _selectedOrderId, orElse: () => null);

    return Column(
      children: [
        _Header(
          activeCount: _orders.where((o) => o['order_status'] != 'completed').length,
          onRefresh: () => _load(showSpinner: false),
        ),
        _StationTabs(
          stations: _stations,
          totalActive: _orders.where((o) => o['order_status'] != 'completed').length,
          countFor: _stationCount,
          selected: _selectedStation,
          onSelected: (key) => setState(() => _selectedStation = key),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _visibleOrders.isEmpty
                    ? Center(
                        child: Text(
                          _selectedStation == 'all' ? 'No orders right now.' : 'No orders for this station right now.',
                          style: const TextStyle(color: _Ui.muted),
                        ),
                      )
                    : _OrderBoard(
                        orders: _visibleOrders,
                        selectedStation: _selectedStation,
                        selectedOrderId: wide ? _selectedOrderId : null,
                        onTap: (id) => _selectOrder(id),
                      ),
              ),
              if (wide)
                Container(
                  width: 360,
                  decoration: const BoxDecoration(color: _Ui.panelBg, border: Border(left: BorderSide(color: _Ui.border))),
                  child: selectedOrder == null
                      ? const Center(child: Text('Select an order to view details.', style: TextStyle(color: _Ui.muted)))
                      : _OrderDetailPanel(
                          order: selectedOrder,
                          busy: _busy.contains(selectedOrder['order_id']),
                          onAdvance: (next) => _advance(selectedOrder, next),
                        ),
                ),
            ],
          ),
        ),
        _PerformanceBar(performance: _performance),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final int activeCount;
  final VoidCallback onRefresh;
  const _Header({required this.activeCount, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: _Ui.border))),
      child: Row(
        children: [
          const Icon(Icons.restaurant_menu, color: _Ui.tanDeep),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kitchen Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _Ui.ink)),
                Text(
                  'Track and manage all kitchen orders in real time',
                  style: TextStyle(fontSize: 12, color: _Ui.muted),
                ),
              ],
            ),
          ),
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: _Ui.green, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          const Text('Live', style: TextStyle(fontSize: 12, color: _Ui.greenText, fontWeight: FontWeight.w600)),
          IconButton(tooltip: 'Refresh', onPressed: onRefresh, icon: const Icon(Icons.refresh, color: _Ui.muted)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Station tabs
// ---------------------------------------------------------------------------

class _StationTabs extends StatelessWidget {
  final List<Map<String, dynamic>> stations;
  final int totalActive;

  /// Open orders that have at least one item for the given station key.
  final int Function(String key) countFor;
  final String selected;
  final ValueChanged<String> onSelected;
  const _StationTabs({
    required this.stations,
    required this.totalActive,
    required this.countFor,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _Pill(
              icon: Icons.receipt_long_outlined,
              label: 'All Orders',
              count: totalActive,
              selected: selected == 'all',
              onTap: () => onSelected('all'),
            ),
            for (final s in stations) ...[
              const SizedBox(width: 8),
              _Pill(
                icon: _stationIcons['${s['key']}'],
                label: '${s['label']}'.replaceAll(' Station', ''),
                count: countFor('${s['key']}'),
                selected: selected == s['key'],
                onTap: () => onSelected('${s['key']}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({required this.icon, required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _Ui.tanDeep : _Ui.pillIdle,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? Colors.white : _Ui.muted),
                const SizedBox(width: 6),
              ],
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: selected ? Colors.white : _Ui.ink)),
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withOpacity(0.28) : _Ui.tanTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? Colors.white : _Ui.tanDeep),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order board: one combined grid of order cards
// ---------------------------------------------------------------------------

class _OrderBoard extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final String selectedStation;
  final int? selectedOrderId;
  final ValueChanged<int> onTap;
  const _OrderBoard({
    required this.orders,
    required this.selectedStation,
    required this.selectedOrderId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // "All Orders" -> null, so each card lists every item of the order.
    final stationKey = selectedStation == 'all' ? null : selectedStation;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 150,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: orders.length,
      itemBuilder: (_, i) {
        final o = orders[i];
        return _OrderCard(
          order: o,
          stationKey: stationKey,
          selected: o['order_id'] == selectedOrderId,
          onTap: () => onTap(o['order_id'] as int),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;

  /// When set, the card lists only this station's items. When null (the
  /// "All Orders" tab) it lists every item, each tagged with its station.
  final String? stationKey;
  final bool selected;
  final VoidCallback onTap;
  const _OrderCard({required this.order, this.stationKey, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = '${order['order_status']}';
    final style = _cardStatusStyle(status);
    final items = stationKey == null ? _asList(order['items']) : _itemsFor(order, stationKey!);
    final itemsText = items.map((i) {
      final base = '${i['quantity']}× ${i['food_name']}';
      if (stationKey != null) return base;
      return '$base (${_capitalize(_itemStation(i))})';
    }).join(', ');
    final tableNumber = order['table_number'] as String?;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? _Ui.tanDeep : _Ui.border, width: selected ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Order #${order['order_id']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Ui.ink)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(20)),
                    child: Text(_cardStatusLabel(status), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: style.fg)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tableNumber ?? _typeLabel('${order['order_type']}'),
                style: const TextStyle(fontSize: 11, color: _Ui.muted),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  itemsText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _Ui.ink, height: 1.3),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 12, color: _Ui.muted),
                  const SizedBox(width: 4),
                  Text(_elapsedLabel(_asNum(order['minutes_ago']).toInt()), style: const TextStyle(fontSize: 11, color: _Ui.muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order detail panel
// ---------------------------------------------------------------------------

class _OrderDetailPanel extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool busy;
  final ScrollController? scrollController;
  final ValueChanged<String> onAdvance;
  const _OrderDetailPanel({required this.order, required this.busy, this.scrollController, required this.onAdvance});

  @override
  Widget build(BuildContext context) {
    final status = '${order['order_status']}';
    final items = _asList(order['items']);
    final allowedNext = (order['allowed_next'] as List<dynamic>? ?? []).map((e) => '$e').toList();
    final tableNumber = order['table_number'] as String?;
    final totalItems = items.fold<int>(0, (sum, i) => sum + _asNum(i['quantity']).toInt());

    final stageIndex = _trackStages.indexOf(status); // -1 while still 'confirmed'
    final nextAction = allowedNext.contains('preparing')
        ? ('preparing', 'Start Preparing')
        : allowedNext.contains('ready')
            ? ('ready', 'Mark as Ready')
            : null;

    final cookingMinutes = _asNum(order['cooking_minutes'] ?? order['minutes_ago']).toInt();
    final elapsedLabel = order['prep_started_at'] != null
        ? (cookingMinutes < 1 ? 'Just started cooking' : 'Cooking for ${_elapsedLabel(cookingMinutes)}')
        : 'Waiting to start · ${_elapsedLabel(_asNum(order['minutes_ago']).toInt())} in queue';

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Order #${order['order_id']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _Ui.ink)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _cardStatusStyle(status).bg, borderRadius: BorderRadius.circular(20)),
                child: Text(_cardStatusLabel(status), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _cardStatusStyle(status).fg)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${tableNumber ?? _typeLabel('${order['order_type']}')} · ${_agoLabel(_asNum(order['minutes_ago']).toInt())}',
            style: const TextStyle(fontSize: 13, color: _Ui.muted),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final stage in _trackStages) _TrackStep(stage: stage, state: _stepState(stage, stageIndex))],
          ),
          const SizedBox(height: 20),
          const Text('Order Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _Ui.ink)),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Text('${item['quantity']}×', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Ui.tanDeep)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${item['food_name']}', style: const TextStyle(fontSize: 13, color: _Ui.ink))),
                  Text(
                    _capitalize(_itemStation(item)),
                    style: const TextStyle(fontSize: 11, color: _Ui.muted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text('Total Items: $totalItems', style: const TextStyle(fontSize: 12, color: _Ui.muted)),
          const SizedBox(height: 18),
          const Text('Special Notes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _Ui.ink)),
          const SizedBox(height: 6),
          const Text('None for this order.', style: TextStyle(fontSize: 13, color: _Ui.muted)),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _Ui.tanTint, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.access_time_filled, size: 20, color: _Ui.tanDeep),
                const SizedBox(width: 10),
                Expanded(child: Text(elapsedLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Ui.tanDeep))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (nextAction != null)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: busy ? null : () => onAdvance(nextAction.$1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Ui.tanDeep,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(nextAction.$2),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _Ui.pillIdle, borderRadius: BorderRadius.circular(12)),
              child: Text(_waitingLabel(status), style: const TextStyle(fontSize: 13, color: _Ui.muted)),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () => _showFullDetails(context, order),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('View Order Details'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _Ui.tanDeep,
                side: const BorderSide(color: _Ui.tanDeep),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _waitingLabel(String status) {
    switch (status) {
      case 'ready':
        return 'Ready — waiting to be served';
      case 'served':
        return 'Served — waiting to be closed out';
      case 'completed':
        return 'Completed';
      default:
        return 'No action needed right now';
    }
  }

  static String _stepState(String stage, int stageIndex) {
    final i = _trackStages.indexOf(stage);
    if (stageIndex < 0) return 'pending'; // still queued, nothing started
    if (i < stageIndex) return 'done';
    if (i == stageIndex) return 'current';
    return 'pending';
  }

  void _showFullDetails(BuildContext context, Map<String, dynamic> order) {
    final items = _asList(order['items']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Order #${order['order_id']}'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text('${item['quantity']}× ${item['food_name']}')),
                        Text(_money(_asNum(item['subtotal']))),
                      ],
                    ),
                  ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(_money(_asNum(order['total_amount'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
      ),
    );
  }
}

class _TrackStep extends StatelessWidget {
  final String stage;
  final String state; // 'done' | 'current' | 'pending'
  const _TrackStep({required this.stage, required this.state});

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (state) {
      case 'done':
        color = _Ui.greenText;
        break;
      case 'current':
        color = _Ui.tanDeep;
        break;
      default:
        color = _Ui.muted.withOpacity(0.4);
    }
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: state == 'pending' ? _Ui.pillIdle : color.withOpacity(0.14),
            shape: BoxShape.circle,
            border: state == 'current' ? Border.all(color: color, width: 1.6) : null,
          ),
          child: Icon(
            state == 'done' ? Icons.check : _trackIcons[stage],
            size: 17,
            color: state == 'pending' ? _Ui.muted.withOpacity(0.6) : color,
          ),
        ),
        const SizedBox(height: 4),
        Text(_trackLabels[stage] ?? stage, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Performance bar
// ---------------------------------------------------------------------------

class _PerformanceBar extends StatelessWidget {
  final Map<String, dynamic> performance;
  const _PerformanceBar({required this.performance});

  @override
  Widget build(BuildContext context) {
    final avgPrep = performance['avgPrepMinutes'];
    final inKitchen = performance['inKitchen'];
    final onTimePct = performance['onTimePct'];
    final delayed = performance['delayedCount'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _Ui.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.local_fire_department_outlined, size: 16, color: _Ui.tanDeep),
            const SizedBox(width: 6),
            const Text('Kitchen Performance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _Ui.ink)),
            const SizedBox(width: 20),
            _PerfStat(label: 'Avg Prep Time', value: avgPrep == null ? '—' : '${avgPrep}m'),
            const SizedBox(width: 20),
            _PerfStat(label: 'In Kitchen', value: '$inKitchen'),
            const SizedBox(width: 20),
            _PerfStat(label: 'On-Time', value: onTimePct == null ? '—' : '$onTimePct%'),
            const SizedBox(width: 20),
            _PerfStat(
              label: 'Delayed Orders',
              value: '$delayed',
              valueColor: (_asNum(delayed).toInt() > 0) ? _Ui.redText : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _PerfStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _PerfStat({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: valueColor ?? _Ui.ink)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: _Ui.muted)),
      ],
    );
  }
}