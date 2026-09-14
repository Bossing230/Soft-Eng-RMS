import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/models/inventory.dart';
import 'package:rms/Frontend/repositories/order_respository.dart';
import 'package:rms/Frontend/repositories/reservation_repositoriy.dart';
import '../../repositories/dashboard_repository.dart';
import '../../repositories/inventory_repository.dart';
import '../../models/order.dart';
import '../../widgets/dashboard_card.dart';

enum _Period { daily, weekly, monthly }

/// A richer Overview page for Admin and Manager, backed entirely by real
/// data: today's summary, a sales trend chart, best-selling items, recent
/// orders, low-stock alerts, and today's per-employee performance.
///
/// Note: there is no "who's currently online" concept in this system (no
/// attendance/clock-in tracking), so this shows real *today's order
/// activity* per active employee rather than a fabricated live-presence
/// indicator.
class RichOverviewPage extends StatefulWidget {
  final bool isAdmin;
  const RichOverviewPage({super.key, this.isAdmin = false});

  @override
  State<RichOverviewPage> createState() => _RichOverviewPageState();
}

class _RichOverviewPageState extends State<RichOverviewPage> {
  final _dashboardRepo = DashboardRepository();
  final _orderRepo = OrderRepository();
  final _inventoryRepo = InventoryRepository();
  final _reservationRepo = ReservationRepository();

  _Period _period = _Period.weekly;
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _salesTrend = [];
  List<Map<String, dynamic>> _bestSellers = [];
  List<RmsOrder> _recentOrders = [];
  List<InventoryItem> _lowStock = [];
  List<Map<String, dynamic>> _staffPerformance = [];
  int _availableTables = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTimeRange _rangeForPeriod() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.daily:
        return DateTimeRange(start: now, end: now);
      case _Period.weekly:
        return DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);
      case _Period.monthly:
        return DateTimeRange(start: now.subtract(const Duration(days: 29)), end: now);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final range = _rangeForPeriod();
      final startStr = DateFormat('yyyy-MM-dd').format(range.start);
      final endStr = DateFormat('yyyy-MM-dd').format(range.end);
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final results = await Future.wait([
        _dashboardRepo.getSummary(),
        _dashboardRepo.getSalesTrend(start: startStr, end: endStr),
        _dashboardRepo.getBestSellers(start: startStr, end: endStr, limit: 5),
        _orderRepo.getAll(),
        _inventoryRepo.getLowStock(),
        _dashboardRepo.getStaffPerformance(date: todayStr),
        _reservationRepo.getAvailableTables(date: todayStr, time: '12:00:00', guestCount: 1),
      ]);

      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _salesTrend = results[1] as List<Map<String, dynamic>>;
        _bestSellers = results[2] as List<Map<String, dynamic>>;
        _recentOrders = (results[3] as List<RmsOrder>).take(4).toList();
        _lowStock = results[4] as List<InventoryItem>;
        _staffPerformance = results[5] as List<Map<String, dynamic>>;
        _availableTables = (results[6] as List).length;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'preparing':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      case 'ready':
        return Colors.green;
      case 'completed':
        return Colors.purple;
      case 'confirmed':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Failed to load overview: $_error'));

    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 18 ? 'Good afternoon' : 'Good evening');
    final s = _summary!;

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$greeting,', style: TextStyle(color: Colors.grey[600])),
                      const Text("Today's overview", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.circle, size: 10, color: Colors.green),
                  label: Text(DateFormat('MMM d, yyyy').format(DateTime.now())),
                  backgroundColor: Colors.grey[100],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: SegmentedButton<_Period>(
                segments: const [
                  ButtonSegment(value: _Period.daily, label: Text('Daily')),
                  ButtonSegment(value: _Period.weekly, label: Text('Weekly')),
                  ButtonSegment(value: _Period.monthly, label: Text('Monthly')),
                ],
                selected: {_period},
                onSelectionChanged: (v) {
                  setState(() => _period = v.first);
                  _load();
                },
              ),
            ),
            const SizedBox(height: 20),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width >= 900 ? 4 : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                DashboardCard(label: "Today's Revenue", value: '₱${s['todaySales'] ?? 0}', icon: Icons.payments_outlined),
                DashboardCard(label: 'Active Orders', value: '${s['pendingOrders'] ?? 0}', icon: Icons.receipt_long),
                DashboardCard(label: 'Available Tables', value: '$_availableTables', icon: Icons.table_bar),
                DashboardCard(label: 'Low Stock Items', value: '${_lowStock.length}', icon: Icons.warning_amber, color: Colors.red),
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 800;
                final chart = _revenueChartCard();
                final topItems = _topItemsCard();
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: chart),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: topItems),
                    ],
                  );
                }
                return Column(children: [chart, const SizedBox(height: 16), topItems]);
              },
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 800;
                final recent = _recentOrdersCard();
                final alerts = _alertsCard();
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: recent),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: alerts),
                    ],
                  );
                }
                return Column(children: [recent, const SizedBox(height: 16), alerts]);
              },
            ),
            const SizedBox(height: 16),
            _staffPerformanceCard(),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, String? subtitle, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _revenueChartCard() {
    if (_salesTrend.isEmpty) {
      return _sectionCard(title: 'Revenue Overview', child: const SizedBox(height: 180, child: Center(child: Text('No completed sales in this period yet.'))));
    }
    final maxY = _salesTrend.map((r) => double.tryParse(r['total_sales'].toString()) ?? 0).fold(0.0, (a, b) => a > b ? a : b);
    return _sectionCard(
      title: 'Revenue Overview',
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            maxY: maxY == 0 ? 10 : maxY * 1.2,
            barGroups: List.generate(_salesTrend.length, (i) {
              final value = double.tryParse(_salesTrend[i]['total_sales'].toString()) ?? 0;
              return BarChartGroupData(x: i, barRods: [BarChartRodData(toY: value, width: 18, borderRadius: BorderRadius.circular(4))]);
            }),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= _salesTrend.length) return const SizedBox.shrink();
                    final day = DateTime.tryParse(_salesTrend[i]['day'] ?? '');
                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(day != null ? DateFormat('E').format(day) : '', style: const TextStyle(fontSize: 11)));
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(drawVerticalLine: false),
          ),
        ),
      ),
    );
  }

  Widget _topItemsCard() {
    if (_bestSellers.isEmpty) {
      return _sectionCard(title: 'Top Items', subtitle: 'This period', child: const Text('No completed orders yet.'));
    }
    final maxSold = _bestSellers.map((i) => int.tryParse(i['total_sold'].toString()) ?? 0).fold(1, (a, b) => a > b ? a : b);
    return _sectionCard(
      title: 'Top Items',
      subtitle: 'This period',
      child: Column(
        children: List.generate(_bestSellers.length, (i) {
          final item = _bestSellers[i];
          final sold = int.tryParse(item['total_sold'].toString()) ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                CircleAvatar(radius: 10, backgroundColor: Colors.grey[200], child: Text('${i + 1}', style: const TextStyle(fontSize: 10))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['food_name'], style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: sold / maxSold, minHeight: 5, backgroundColor: Colors.grey[200]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text('$sold', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _recentOrdersCard() {
    return _sectionCard(
      title: 'Recent Orders',
      child: _recentOrders.isEmpty
          ? const Text('No orders yet.')
          : Column(
              children: _recentOrders.map((o) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 16, backgroundColor: Colors.grey[100], child: Text(o.tableNumber ?? '—', style: const TextStyle(fontSize: 10))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Order #${o.orderId}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${o.items.length} items', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      Chip(label: Text(o.orderStatus, style: const TextStyle(fontSize: 10)), backgroundColor: _statusColor(o.orderStatus).withOpacity(0.15), visualDensity: VisualDensity.compact),
                      const SizedBox(width: 8),
                      Text('₱${o.totalAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _alertsCard() {
    return _sectionCard(
      title: 'Alerts',
      child: _lowStock.isEmpty
          ? const Text('No active alerts.')
          : Column(
              children: _lowStock.map((item) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Low stock: ${item.ingredientName}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.red)),
                            Text('${item.quantity} ${item.unit} remaining', style: TextStyle(fontSize: 11, color: Colors.red[700])),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _staffPerformanceCard() {
    return _sectionCard(
      title: 'Staff Performance',
      subtitle: "Today — active employees' real order activity (not live presence)",
      child: _staffPerformance.isEmpty
          ? const Text('No active employees found.')
          : Column(
              children: _staffPerformance.map((row) {
                final name = row['name'] as String;
                final initials = name.isNotEmpty ? name.trim().split(' ').map((p) => p[0]).take(2).join().toUpperCase() : '?';
                final orders = row['order_count'];
                final sales = row['total_sales'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 18, backgroundColor: Colors.grey[200], child: Text(initials, style: const TextStyle(fontSize: 12))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(row['role_name'], style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('₱$sales', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          Text('$orders orders', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}