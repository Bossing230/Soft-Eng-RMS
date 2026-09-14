import 'package:flutter/material.dart';
import '../../repositories/dashboard_repository.dart';
import '../../widgets/dashboard_card.dart';

class DashboardOverviewPage extends StatefulWidget {
  final bool isAdmin;
  const DashboardOverviewPage({super.key, this.isAdmin = false});

  @override
  State<DashboardOverviewPage> createState() => _DashboardOverviewPageState();
}

class _DashboardOverviewPageState extends State<DashboardOverviewPage> {
  final _repo = DashboardRepository();
  Map<String, dynamic>? _summary;
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
      final data = await _repo.getSummary();
      setState(() => _summary = data);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Failed to load dashboard: $_error'));

    final s = _summary!;
    final cards = <Widget>[
      DashboardCard(label: "Today's Orders", value: '${s['todayOrders'] ?? 0}', icon: Icons.receipt_long),
      DashboardCard(label: "Today's Sales", value: '₱${s['todaySales'] ?? 0}', icon: Icons.payments),
      DashboardCard(label: 'Pending Orders', value: '${s['pendingOrders'] ?? 0}', icon: Icons.hourglass_top),
      DashboardCard(label: 'Active Reservations', value: '${s['activeReservations'] ?? 0}', icon: Icons.event_seat),
      DashboardCard(label: 'Low Stock Alerts', value: '${s['lowStockCount'] ?? 0}', icon: Icons.warning_amber, color: Colors.orange),
      if (widget.isAdmin) ...[
        DashboardCard(label: 'Total Employees', value: '${s['totalEmployees'] ?? 0}', icon: Icons.badge),
        DashboardCard(label: 'Total Revenue', value: '₱${s['totalRevenue'] ?? 0}', icon: Icons.trending_up),
      ],
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          mainAxisExtent: 100,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: cards.length,
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }
}