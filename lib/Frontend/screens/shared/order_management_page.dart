import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/repositories/order_repository.dart';

import '../../models/order.dart';

// ---------------------------------------------------------------------------
// Design tokens, taken from the orders design.
// ---------------------------------------------------------------------------
class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const tanDeep = Color(0xFFB98A5E);
  static const tanTint = Color(0xFFF0DFCF);
  static const pillIdle = Color(0xFFEFE9E0);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
  static const redText = Color(0xFFE53935);
}

final _money = NumberFormat('#,##0.##');

const _statusLabels = {
  'pending': 'Pending',
  'confirmed': 'Confirmed',
  'preparing': 'Preparing',
  'ready': 'Ready',
  'served': 'Served',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
};

class _StatusStyle {
  final Color bg;
  final Color fg;
  const _StatusStyle(this.bg, this.fg);
}

_StatusStyle _styleFor(String status) {
  switch (status) {
    case 'pending':
      return const _StatusStyle(Color(0xFFFFF4D6), Color(0xFFB36B00));
    case 'confirmed':
      return const _StatusStyle(Color(0xFFFFE9C7), Color(0xFFA65F00));
    case 'preparing':
      return const _StatusStyle(Color(0xFFE3F2FD), Color(0xFF1E88E5));
    case 'ready':
      return const _StatusStyle(Color(0xFFE8F5E9), Color(0xFF2E7D32));
    case 'served':
      return const _StatusStyle(Color(0xFFE0F2F1), Color(0xFF00796B));
    case 'completed':
      return const _StatusStyle(Color(0xFFF3E5F5), Color(0xFF8E24AA));
    case 'cancelled':
      return const _StatusStyle(Color(0xFFFFEBEE), Color(0xFFC62828));
    default:
      return const _StatusStyle(_Ui.pillIdle, _Ui.muted);
  }
}

String _statusLabel(String status) => _statusLabels[status] ?? status;

String _menuLabel(String status) {
  switch (status) {
    case 'confirmed':
      return 'Confirmed (send to kitchen)';
    case 'cancelled':
      return 'Cancel order';
    default:
      return _statusLabel(status);
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

const _methodNames = {'cash': 'Cash', 'card': 'Card', 'ewallet': 'E-wallet', 'online': 'Online'};

String _paymentLabel(RmsOrder order) {
  final method = order.paymentMethod;
  if (method == null) return 'Unpaid';
  final name = _methodNames[method] ?? method;
  return order.paymentStatus == 'paid' ? name : '$name (awaiting)';
}

/// The little square: the table for dine-in, TO for takeout, DL for delivery.
String _badgeText(RmsOrder order) {
  switch (order.orderType) {
    case 'takeout':
      return 'TO';
    case 'delivery':
      return 'DL';
    default:
      final table = order.tableNumber?.trim() ?? '';
      if (table.isEmpty) return 'DI';
      return RegExp(r'^\d').hasMatch(table) ? 'T$table' : table.toUpperCase();
  }
}

String _itemsText(RmsOrder order) {
  if (order.items.isEmpty) return 'No items';
  return order.items.map((i) => '${i.quantity}× ${i.foodName}').join(', ');
}

String _ago(int? minutes) {
  if (minutes == null) return '';
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '${minutes}m ago';
  if (minutes < 60 * 24) return '${minutes ~/ 60}h ago';
  return '${minutes ~/ (60 * 24)}d ago';
}

/// Confirmed orders count under the Pending filter.
String _group(RmsOrder order) => order.orderStatus == 'confirmed' ? 'pending' : order.orderStatus;

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Orders for Manager and Cashier: today's orders plus anything still open,
/// filtered by status, with a dropdown on each card to move it forward. The
/// server decides which statuses the signed-in role may choose.
class OrderManagementPage extends StatefulWidget {
  final bool canForceCancel;
  const OrderManagementPage({super.key, this.canForceCancel = false});

  @override
  State<OrderManagementPage> createState() => _OrderManagementPageState();
}

class _OrderManagementPageState extends State<OrderManagementPage> {
  final _repo = OrderRepository();
  Timer? _timer;
  List<RmsOrder> _orders = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    // New orders and status changes from other devices show up on their own.
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(showSpinner: false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true, bool notifyOnError = false}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _repo.getBoard();
      if (!mounted) return;
      setState(() {
        _orders = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_orders.isEmpty) _error = e.toString();
      });
      if (notifyOnError && _orders.isNotEmpty) _snack('Could not refresh: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  int _count(String key) {
    if (key == 'all') return _orders.where((o) => o.orderStatus != 'cancelled').length;
    return _orders.where((o) => _group(o) == key).length;
  }

  List<RmsOrder> get _visible {
    if (_filter == 'all') return _orders.where((o) => o.orderStatus != 'cancelled').toList();
    return _orders.where((o) => _group(o) == _filter).toList();
  }

  Future<bool> _confirmCancel(RmsOrder order) async {
    final paid = order.paymentStatus == 'paid';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel order #${order.orderId}?'),
        content: Text(
          paid
              ? 'This order is already paid. Cancelling it does not refund the payment.'
              : "This can't be undone.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep order')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel order', style: TextStyle(color: _Ui.redText)),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _changeStatus(RmsOrder order, String next) async {
    if (next == 'cancelled' && !await _confirmCancel(order)) return;
    setState(() => _busy.add(order.orderId));
    try {
      await _repo.updateStatus(order.orderId, next);
      await _load(showSpinner: false);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy.remove(order.orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pills = <_PillData>[
      _PillData('all', 'All', _count('all')),
      _PillData('pending', 'Pending', _count('pending')),
      _PillData('preparing', 'Preparing', _count('preparing')),
      _PillData('ready', 'Ready', _count('ready')),
      _PillData('served', 'Served', _count('served')),
      _PillData('completed', 'Completed', _count('completed')),
      if (_count('cancelled') > 0 || _filter == 'cancelled') _PillData('cancelled', 'Cancelled', _count('cancelled')),
    ];

    return Column(
      children: [
        _OrdersHeader(
          pendingCount: _count('pending'),
          preparingCount: _count('preparing'),
          readyCount: _count('ready'),
          pills: pills,
          selected: _filter,
          onSelect: (key) => setState(() => _filter = key),
          onRefresh: () => _load(showSpinner: false, notifyOnError: true),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _orders.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    final visible = _visible;
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false, notifyOnError: true),
      child: visible.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _EmptyState(
                  message: _filter == 'all'
                      ? 'No orders yet today.'
                      : 'No ${_statusLabel(_filter).toLowerCase()} orders right now.',
                ),
              ],
            )
          : GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 400,
                mainAxisExtent: 236,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: visible.length,
              itemBuilder: (_, i) {
                final order = visible[i];
                return _OrderCard(
                  order: order,
                  busy: _busy.contains(order.orderId),
                  canCancel: widget.canForceCancel,
                  onStatus: (next) => _changeStatus(order, next),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header: summary chips, refresh, filter pills
// ---------------------------------------------------------------------------

class _PillData {
  final String key;
  final String label;
  final int count;
  const _PillData(this.key, this.label, this.count);
}

class _OrdersHeader extends StatelessWidget {
  final int pendingCount;
  final int preparingCount;
  final int readyCount;
  final List<_PillData> pills;
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onRefresh;
  const _OrdersHeader({
    required this.pendingCount,
    required this.preparingCount,
    required this.readyCount,
    required this.pills,
    required this.selected,
    required this.onSelect,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _Ui.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryChip(count: pendingCount, status: 'pending'),
                    _SummaryChip(count: preparingCount, status: 'preparing'),
                    _SummaryChip(count: readyCount, status: 'ready'),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, color: _Ui.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in pills) _FilterPill(data: p, selected: p.key == selected, onTap: () => onSelect(p.key)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "Showing today's orders and any order that is still open.",
            style: TextStyle(fontSize: 11, color: _Ui.muted),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final int count;
  final String status;
  const _SummaryChip({required this.count, required this.status});

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        '$count ${_statusLabel(status)}',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: style.fg),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final _PillData data;
  final bool selected;
  final VoidCallback onTap;
  const _FilterPill({required this.data, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _Ui.tanDeep : _Ui.pillIdle,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : _Ui.muted,
                ),
              ),
              if (data.count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white.withOpacity(0.28) : _Ui.tanTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${data.count}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : _Ui.tanDeep,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order card
// ---------------------------------------------------------------------------

class _OrderCard extends StatelessWidget {
  final RmsOrder order;
  final bool busy;
  final bool canCancel;
  final ValueChanged<String> onStatus;
  const _OrderCard({required this.order, required this.busy, required this.canCancel, required this.onStatus});

  @override
  Widget build(BuildContext context) {
    // The server already limits this to what the signed-in role may set.
    final options = order.allowedNext.where((s) => s != 'cancelled' || canCancel).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Ui.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TableBadge(text: _badgeText(order)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${order.orderId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _Ui.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_typeLabel(order.orderType)} · ${_paymentLabel(order)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _Ui.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(status: order.orderStatus),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: _Ui.border),
          const SizedBox(height: 12),
          Expanded(
            child: Text(
              _itemsText(order),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.4, color: _Ui.muted),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₱${_money.format(order.totalAmount)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: _Ui.ink),
                  ),
                  Text(_ago(order.minutesAgo), style: const TextStyle(fontSize: 11, color: _Ui.muted)),
                ],
              ),
              const Spacer(),
              _StatusMenu(current: order.orderStatus, options: options, busy: busy, onSelected: onStatus),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableBadge extends StatelessWidget {
  final String text;
  const _TableBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _Ui.tanTint, borderRadius: BorderRadius.circular(10)),
      child: FittedBox(
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Ui.tanDeep)),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        _statusLabel(status),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: style.fg),
      ),
    );
  }
}

/// The small "Preparing v" control: tap it to move the order to a later status.
class _StatusMenu extends StatelessWidget {
  final String current;
  final List<String> options;
  final bool busy;
  final ValueChanged<String> onSelected;
  const _StatusMenu({required this.current, required this.options, required this.busy, required this.onSelected});

  Widget _pill({bool arrow = false, bool spinner = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: _Ui.pillIdle, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Text(_statusLabel(current), style: const TextStyle(fontSize: 12, color: _Ui.ink)),
          if (arrow) ...[
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: _Ui.muted),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (busy) return _pill(spinner: true);
    if (options.isEmpty) return _pill();
    return PopupMenuButton<String>(
      tooltip: 'Change status',
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final s in options)
          PopupMenuItem<String>(
            value: s,
            child: Text(_menuLabel(s), style: TextStyle(color: s == 'cancelled' ? _Ui.redText : null)),
          ),
      ],
      child: _pill(arrow: true),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty and error states
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Center(child: Text(message, style: const TextStyle(color: _Ui.muted))),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: _Ui.muted),
            const SizedBox(height: 12),
            const Text("Couldn't load the orders", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _Ui.muted)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}