import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../repositories/dashboard_repository.dart';
import '../shared/role_scaffold.dart';

// ---------------------------------------------------------------------------
// Design tokens, taken from the Summary design.
// ---------------------------------------------------------------------------
class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const tanDeep = Color(0xFFB98A5E);
  static const tanTint = Color(0xFFF0DFCF);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
  static const green = Color(0xFF4CAF50);
  static const blue = Color(0xFF2196F3);
  static const amber = Color(0xFFFFC107);
}

final _money = NumberFormat('#,##0');

List<Map<String, dynamic>> _asList(dynamic v) =>
    ((v as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
num _asNum(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);

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

_StatusStyle _statusStyle(String status) {
  switch (status) {
    case 'pending':
      return const _StatusStyle(Color(0xFFFFF4D6), Color(0xFFB36B00));
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
      return const _StatusStyle(Color(0xFFEFE9E0), _Ui.muted);
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

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// The cashier's own dashboard: today's sales, what needs attention right
/// now, quick actions to the other tabs, and a few recent orders.
class CashierSummaryPage extends StatefulWidget {
  const CashierSummaryPage({super.key});

  @override
  State<CashierSummaryPage> createState() => _CashierSummaryPageState();
}

class _CashierSummaryPageState extends State<CashierSummaryPage> {
  final _repo = DashboardRepository();
  Timer? _timer;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh(showSpinner: false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _repo.getCashierSummary();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_data == null) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40, color: _Ui.muted),
              const SizedBox(height: 12),
              const Text("Couldn't load the summary", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: _Ui.muted)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _refresh, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final d = _data!;
    final mySales = Map<String, dynamic>.from(d['mySales'] ?? {});
    final recentOrders = _asList(d['recentOrders']);

    return RefreshIndicator(
      onRefresh: () => _refresh(showSpinner: false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 800;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(wide ? 24 : 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  children: [
                    _StatCards(
                      mySalesToday: _asNum(mySales['today']).toDouble(),
                      myOrdersToday: _asNum(mySales['ordersToday']).toInt(),
                      pendingOrders: _asNum(d['pendingOrders']).toInt(),
                      availableTables: _asNum(d['availableTables']).toInt(),
                      avgOrderValue: _asNum(d['avgOrderValue']).toDouble(),
                    ),
                    const SizedBox(height: 16),
                    const _QuickActions(),
                    const SizedBox(height: 16),
                    _RecentOrdersCard(orders: recentOrders),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared panel shell
// ---------------------------------------------------------------------------

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Panel({required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Ui.border),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Stat cards
// ---------------------------------------------------------------------------

class _StatCards extends StatelessWidget {
  final double mySalesToday;
  final int myOrdersToday;
  final int pendingOrders;
  final int availableTables;
  final double avgOrderValue;
  const _StatCards({
    required this.mySalesToday,
    required this.myOrdersToday,
    required this.pendingOrders,
    required this.availableTables,
    required this.avgOrderValue,
  });

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _StatCard(
        icon: Icons.payments_outlined,
        color: _Ui.tanDeep,
        value: '₱${_money.format(mySalesToday)}',
        label: 'My sales today',
        badgeText: '+$myOrdersToday ${myOrdersToday == 1 ? 'order' : 'orders'}',
      ),
      _StatCard(
        icon: Icons.assignment_outlined,
        color: _Ui.amber,
        value: '$pendingOrders',
        label: 'Pending orders',
      ),
      _StatCard(
        icon: Icons.table_bar_outlined,
        color: _Ui.green,
        value: '$availableTables',
        label: 'Available tables',
      ),
      _StatCard(
        icon: Icons.trending_up,
        color: _Ui.blue,
        value: '₱${_money.format(avgOrderValue)}',
        label: 'Avg order value',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards.map((c) => SizedBox(width: width, child: c)).toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? badgeText;
  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 22, color: color),
              ),
              const Spacer(),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF2E9E4F).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    badgeText!,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2E9E4F)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: _Ui.ink)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 13, color: _Ui.muted)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions
// ---------------------------------------------------------------------------

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quick actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: _Ui.ink)),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final items = [
                _QuickAction(icon: Icons.add_shopping_cart, label: 'New order', color: _Ui.tanDeep, tintBg: _Ui.tanTint, target: 'POS'),
                _QuickAction(icon: Icons.receipt_long_outlined, label: 'View orders', color: _Ui.blue, tintBg: const Color(0xFFE3F2FD), target: 'Orders'),
                _QuickAction(icon: Icons.table_bar_outlined, label: 'Tables', color: _Ui.green, tintBg: const Color(0xFFE8F5E9), target: 'Tables'),
              ];
              const gap = 16.0;
              final narrow = constraints.maxWidth < 560;
              if (narrow) {
                return Column(
                  children: [for (final i in items) Padding(padding: const EdgeInsets.only(bottom: gap), child: i)],
                );
              }
              final width = (constraints.maxWidth - gap * (items.length - 1)) / items.length;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: items.map((i) => SizedBox(width: width, child: i)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color tintBg;
  final String target;
  const _QuickAction({required this.icon, required this.label, required this.color, required this.tintBg, required this.target});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tintBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => RoleScaffoldNavigator.goTo(context, target),
        child: Container(
          height: 92,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent orders
// ---------------------------------------------------------------------------

class _RecentOrdersCard extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  const _RecentOrdersCard({required this.orders});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Recent orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: _Ui.ink)),
              const Spacer(),
              TextButton(
                onPressed: () => RoleScaffoldNavigator.goTo(context, 'Orders'),
                style: TextButton.styleFrom(foregroundColor: _Ui.tanDeep, padding: EdgeInsets.zero),
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No orders yet today.', style: TextStyle(color: _Ui.muted)),
            )
          else
            for (var i = 0; i < orders.length; i++) ...[
              _RecentOrderRow(order: orders[i]),
              if (i < orders.length - 1) const Divider(height: 20, color: _Ui.border),
            ],
        ],
      ),
    );
  }
}

class _RecentOrderRow extends StatelessWidget {
  final Map<String, dynamic> order;
  const _RecentOrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = '${order['order_status']}';
    final style = _statusStyle(status);
    final tableNumber = order['table_number'] as String?;
    final badgeText = tableNumber ?? (order['order_type'] == 'takeout' ? 'TO' : 'DL');
    final itemsCount = _asNum(order['items_count']).toInt();

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _Ui.tanTint, borderRadius: BorderRadius.circular(10)),
          child: Text(badgeText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _Ui.tanDeep)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order #${order['order_id']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _Ui.ink)),
              Text(
                '$itemsCount ${itemsCount == 1 ? 'item' : 'items'} · ${_typeLabel('${order['order_type']}')}',
                style: const TextStyle(fontSize: 12, color: _Ui.muted),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(20)),
              child: Text(
                _statusLabels[status] ?? status,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: style.fg),
              ),
            ),
            const SizedBox(height: 4),
            Text('₱${_money.format(_asNum(order['total_amount']))}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Ui.ink)),
          ],
        ),
      ],
    );
  }
}