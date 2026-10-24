import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../repositories/dashboard_repository.dart';
import '../../widgets/dashboard_card.dart';
import 'role_scaffold.dart';

enum _Period { daily, weekly, monthly }

final _money = NumberFormat('#,##0.00');
String _peso(num v) => '₱${_money.format(v)}';

List<Map<String, dynamic>> _asList(dynamic v) =>
    ((v as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
Map<String, dynamic> _asMap(dynamic v) => Map<String, dynamic>.from((v as Map?) ?? const {});
num _asNum(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);

/// A round step (1, 2, 5 x 10^n) that gives roughly four gridlines, so the
/// chart's side numbers are clean (200, 400, 600...) and never like 790.6.
double _niceInterval(double max) {
  if (max <= 0) return 1000;
  final rough = max / 4;
  final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final n = rough / magnitude;
  final nice = n <= 1 ? 1.0 : (n <= 2 ? 2.0 : (n <= 5 ? 5.0 : 10.0));
  return nice * magnitude;
}

/// ₱800, ₱1.2k, ₱15k: short enough to always fit beside the chart.
String _compactPeso(double v) {
  if (v >= 1000) {
    final k = v / 1000;
    return '₱${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}k';
  }
  return '₱${v.toStringAsFixed(0)}';
}

String _hourShort(int h) => '${h % 12 == 0 ? 12 : h % 12}${h < 12 ? 'a' : 'p'}';
String _hourLong(int h) => '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}';

/// The Administrator's Overview, backed entirely by real data from
/// `GET /reports/admin-overview`.
///
/// All three periods arrive in one response, so switching Daily / Weekly /
/// Monthly happens instantly with no loading screen. The page then refreshes
/// itself in the background every 20 seconds, so Active Orders and Low Stock
/// stay current while orders are being placed.
class RichOverviewPage extends StatefulWidget {
  final bool isAdmin;
  const RichOverviewPage({super.key, this.isAdmin = false});

  @override
  State<RichOverviewPage> createState() => _RichOverviewPageState();
}

class _RichOverviewPageState extends State<RichOverviewPage> {
  final _repo = DashboardRepository();
  Timer? _timer;

  _Period _period = _Period.weekly;
  Map<String, dynamic>? _data;
  bool _loading = true; // only true until the very first answer arrives
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Fetches fresh data. A failed background refresh keeps the last good data
  /// on screen; a failed pull-to-refresh tells the user.
  Future<void> _load({bool manual = false}) async {
    try {
      final data = await _repo.getAdminOverview();
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
          _error = e.toString();
          _loading = false;
        });
      } else if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not refresh: $e')));
      }
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  // ---- period helpers ----

  Map<String, dynamic> get _periodData => _asMap(_asMap(_data!['periods'])[_period.name]);

  String get _revenueLabel {
    switch (_period) {
      case _Period.daily:
        return "Today's Revenue";
      case _Period.weekly:
        return 'Weekly Revenue';
      case _Period.monthly:
        return 'Monthly Revenue';
    }
  }

  String get _revenueNote {
    switch (_period) {
      case _Period.daily:
        return 'Starts again at midnight';
      case _Period.weekly:
        return 'Last 7 days, today included';
      case _Period.monthly:
        return 'Last 30 days, this week included';
    }
  }

  String get _chartSubtitle {
    switch (_period) {
      case _Period.daily:
        return 'Today, by hour';
      case _Period.weekly:
        return 'Last 7 days';
      case _Period.monthly:
        return 'Last 30 days';
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

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_data == null) return _ErrorView(message: _error ?? 'Something went wrong.', onRetry: _retry);

    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 18 ? 'Good afternoon' : 'Good evening');

    final revenue = _asNum(_asMap(_periodData['summary'])['revenue']);
    final active = _asMap(_data!['activeOrders']);
    final lowStock = _asMap(_data!['lowStock']);
    final lowCount = _asNum(lowStock['count']).toInt();
    final lowItems = _asList(lowStock['items']);

    return RefreshIndicator(
      onRefresh: () => _load(manual: true),
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
                // Everything is already loaded, so this just swaps the numbers.
                onSelectionChanged: (v) => setState(() => _period = v.first),
              ),
            ),
            const SizedBox(height: 20),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                mainAxisExtent: 108,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              children: [
                DashboardCard(
                  label: _revenueLabel,
                  value: _peso(revenue),
                  icon: Icons.payments_outlined,
                  subtitle: _revenueNote,
                ),
                DashboardCard(
                  label: 'Active Orders',
                  value: '${_asNum(active['total']).toInt()}',
                  icon: Icons.receipt_long,
                  subtitle: _activeNote(_asMap(active['byStatus'])),
                  onTap: () => RoleScaffoldNavigator.goTo(context, 'Orders'),
                ),
                DashboardCard(
                  label: 'Available Tables',
                  value: '${_asNum(_data!['availableTables']).toInt()}',
                  icon: Icons.table_bar,
                ),
                DashboardCard(
                  label: 'Low Stock Items',
                  value: '$lowCount',
                  icon: Icons.warning_amber,
                  color: lowCount > 0 ? Colors.red : Colors.green,
                  subtitle: _lowStockNote(lowCount, lowItems),
                  onTap: () => RoleScaffoldNavigator.goTo(context, 'Inventory'),
                ),
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
                final alerts = _alertsCard(lowCount, lowItems);
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

  /// "2 preparing · 1 ready", or "No open orders".
  String _activeNote(Map<String, dynamic> byStatus) {
    const order = ['pending', 'confirmed', 'preparing', 'ready', 'served'];
    final parts = [
      for (final s in order)
        if (_asNum(byStatus[s]) > 0) '${_asNum(byStatus[s]).toInt()} $s',
    ];
    return parts.isEmpty ? 'No open orders' : parts.join(' · ');
  }

  String _lowStockNote(int count, List<Map<String, dynamic>> items) {
    if (count == 0) return 'Everything is stocked';
    final names = items.take(2).map((i) => '${i['ingredient_name']}').join(', ');
    return count > 2 ? '$names +${count - 2} more' : names;
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

  // ---- revenue chart ----

  String _axisLabel(int i, List<Map<String, dynamic>> buckets) {
    switch (_period) {
      case _Period.daily:
        return i % 3 == 0 ? _hourShort(_asNum(buckets[i]['key']).toInt()) : '';
      case _Period.weekly:
        final day = DateTime.tryParse('${buckets[i]['key']}');
        return day == null ? '' : DateFormat('E').format(day);
      case _Period.monthly:
        if (i % 5 != 0) return '';
        final day = DateTime.tryParse('${buckets[i]['key']}');
        return day == null ? '' : DateFormat('MMM d').format(day);
    }
  }

  String _tooltipLabel(int i, List<Map<String, dynamic>> buckets) {
    if (_period == _Period.daily) return _hourLong(_asNum(buckets[i]['key']).toInt());
    final day = DateTime.tryParse('${buckets[i]['key']}');
    return day == null ? '' : DateFormat('EEE, MMM d').format(day);
  }

  Widget _revenueChartCard() {
    final buckets = _asList(_periodData['buckets']);
    final values = buckets.map((b) => _asNum(b['revenue']).toDouble()).toList();
    final peak = values.isEmpty ? 0.0 : values.reduce(math.max);

    if (peak <= 0) {
      return _sectionCard(
        title: 'Revenue Overview',
        subtitle: _chartSubtitle,
        child: const SizedBox(height: 200, child: Center(child: Text('No completed sales in this period yet.'))),
      );
    }

    const axisStyle = TextStyle(fontSize: 11, color: Color(0xFF7A7A7A));
    final interval = _niceInterval(peak);
    final maxY = math.max(interval * 2, ((peak * 1.05) / interval).ceil() * interval);
    final barWidth = _period == _Period.weekly ? 18.0 : 7.0;

    return _sectionCard(
      title: 'Revenue Overview',
      subtitle: _chartSubtitle,
      child: SizedBox(
        height: 240,
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: maxY,
            barGroups: List.generate(buckets.length, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    width: barWidth,
                    color: const Color(0xFFB98A5E),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ],
              );
            }),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 52,
                  interval: interval,
                  getTitlesWidget: (value, meta) => Text(_compactPeso(value), style: axisStyle, softWrap: false),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final i = value.round();
                    if ((value - i).abs() > 0.001 || i < 0 || i >= buckets.length) return const SizedBox.shrink();
                    final label = _axisLabel(i, buckets);
                    if (label.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(label, style: axisStyle, softWrap: false),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFEFE8DE), strokeWidth: 1),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                  '${_tooltipLabel(group.x, buckets)}\n${_peso(rod.toY)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- top items ----

  Widget _topItemsCard() {
    final items = _asList(_periodData['topItems']);
    if (items.isEmpty) {
      return _sectionCard(title: 'Top Items', subtitle: _chartSubtitle, child: const Text('No completed orders yet.'));
    }
    final maxSold = items.map((i) => _asNum(i['total_sold']).toInt()).fold(1, (a, b) => a > b ? a : b);
    return _sectionCard(
      title: 'Top Items',
      subtitle: _chartSubtitle,
      child: Column(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final sold = _asNum(item['total_sold']).toInt();
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
                      Text('${item['food_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
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

  // ---- recent orders ----

  Widget _recentOrdersCard() {
    final orders = _asList(_data!['recentOrders']);
    return _sectionCard(
      title: 'Recent Orders',
      child: orders.isEmpty
          ? const Text('No orders yet.')
          : Column(
              children: orders.map((o) {
                final status = '${o['order_status']}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.grey[100],
                        child: Text('${o['table_number'] ?? '—'}', style: const TextStyle(fontSize: 10)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Order #${o['order_id']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${_asNum(o['items_count']).toInt()} items', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(status, style: const TextStyle(fontSize: 10)),
                        backgroundColor: _statusColor(status).withOpacity(0.15),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      Text('₱${_asNum(o['total_amount']).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  // ---- alerts ----

  Widget _alertsCard(int lowCount, List<Map<String, dynamic>> items) {
    return _sectionCard(
      title: 'Alerts',
      child: lowCount == 0
          ? const Text('No active alerts.')
          : Column(
              children: [
                for (final item in items)
                  Builder(builder: (context) {
                    final isOut = '${item['status']}' == 'out' || _asNum(item['quantity']) <= 0;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => RoleScaffoldNavigator.goTo(context, 'Inventory'),
                      child: Container(
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
                                  Text(
                                    '${isOut ? 'Out of stock' : 'Low stock'}: ${item['ingredient_name']}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.red),
                                  ),
                                  Text(
                                    isOut ? 'None remaining' : '${_asNum(item['quantity'])} ${item['unit']} remaining',
                                    style: TextStyle(fontSize: 11, color: Colors.red[700]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                if (lowCount > items.length)
                  Text('+ ${lowCount - items.length} more in Inventory', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
    );
  }

  // ---- staff performance ----

  Widget _staffPerformanceCard() {
    final staff = _asList(_data!['staffPerformance']);
    return _sectionCard(
      title: 'Staff Performance',
      subtitle: "Today's real order activity for each active employee",
      child: staff.isEmpty
          ? const Text('No active employees found.')
          : Column(
              children: staff.map((row) {
                final name = '${row['name']}';
                final initials = name.trim().isEmpty
                    ? '?'
                    : name.trim().split(RegExp(r'\s+')).map((p) => p[0]).take(2).join().toUpperCase();
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
                            Text('${row['role_name']}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_peso(_asNum(row['total_sales'])), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          Text('${_asNum(row['order_count']).toInt()} orders', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
            const Icon(Icons.cloud_off_outlined, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text("Couldn't load the overview", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}