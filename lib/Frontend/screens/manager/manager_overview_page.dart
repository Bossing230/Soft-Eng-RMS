import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../repositories/dashboard_repository.dart';

// ---------------------------------------------------------------------------
// Design tokens, taken from the manager dashboard design.
// ---------------------------------------------------------------------------
class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const gridLine = Color(0xFFEFE8DE);
  static const tan = Color(0xFFD4A574);
  static const tanDeep = Color(0xFFB98A5E);
  static const tanTint = Color(0xFFF0DFCF);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
  static const green = Color(0xFF4CAF50);
  static const blue = Color(0xFF2196F3);
  static const amber = Color(0xFFFFC107);
  static const red = Color(0xFFF44336);
}

final _money = NumberFormat('#,##0');

List<Map<String, dynamic>> _asList(dynamic v) =>
    ((v as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
Map<String, dynamic> _asMap(dynamic v) => Map<String, dynamic>.from((v as Map?) ?? const {});
num _asNum(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Manager overview: stat cards, 7-day sales trend, top sellers, alerts and
/// staff activity, all from `GET /reports/manager-overview`.
class ManagerOverviewPage extends StatefulWidget {
  const ManagerOverviewPage({super.key});

  @override
  State<ManagerOverviewPage> createState() => _ManagerOverviewPageState();
}

class _ManagerOverviewPageState extends State<ManagerOverviewPage> {
  final _repo = DashboardRepository();
  Timer? _refreshTimer;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Fetches fresh data. A failed background refresh keeps the last good data
  /// on screen; a failed pull-to-refresh tells the user.
  Future<void> _refresh({bool manual = false}) async {
    try {
      final data = await _repo.getManagerOverview();
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
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_data == null) return _ErrorView(message: _error ?? 'Something went wrong.', onRetry: _retry);

    final d = _data!;
    final topSelling = _TopSellingCard(items: _asList(d['topItems']));
    final alerts = _AlertsCard(alerts: _asList(d['alerts']));

    return RefreshIndicator(
      onRefresh: () => _refresh(manual: true),
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
                    _StatCards(data: d),
                    const SizedBox(height: 16),
                    _SalesTrendCard(trend: _asList(d['trend'])),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: topSelling),
                          const SizedBox(width: 16),
                          Expanded(child: alerts),
                        ],
                      )
                    else ...[
                      topSelling,
                      const SizedBox(height: 16),
                      alerts,
                    ],
                    const SizedBox(height: 16),
                    _StaffActivityCard(staff: _asList(d['staffActivity']), attendanceReady: d['attendanceReady'] != false),
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
// Shared building blocks
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

class _PanelTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _PanelTitle(this.title, {this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: _Ui.ink)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: const TextStyle(fontSize: 13, color: _Ui.muted)),
        ],
      ],
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
            const Text("Couldn't load the dashboard", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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

// ---------------------------------------------------------------------------
// Stat cards
// ---------------------------------------------------------------------------

class _StatCards extends StatelessWidget {
  final Map<String, dynamic> data;
  const _StatCards({required this.data});

  @override
  Widget build(BuildContext context) {
    final today = _asMap(data['today']);
    final staff = _asMap(data['staff']);
    final change = today['salesChangePct'];

    final cards = <Widget>[
      _StatCard(
        icon: Icons.payments_outlined,
        color: _Ui.tanDeep,
        value: '₱${_money.format(_asNum(today['sales']))}',
        label: "Today's sales",
        changePct: change is num ? change.round() : null,
      ),
      _StatCard(
        icon: Icons.receipt_long_outlined,
        color: _Ui.blue,
        value: _money.format(_asNum(today['orders'])),
        label: 'Total orders',
      ),
      _StatCard(
        icon: Icons.groups_outlined,
        color: _Ui.green,
        value: '${_asNum(staff['onDuty']).toInt()}/${_asNum(staff['total']).toInt()}',
        label: 'Staff on duty',
      ),
      _StatCard(
        icon: Icons.inventory_2_outlined,
        color: _Ui.red,
        value: '${_asNum(data['lowStockCount']).toInt()}',
        label: 'Low stock alerts',
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
  final int? changePct;
  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.changePct,
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
              if (changePct != null) _ChangeBadge(pct: changePct!),
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: _Ui.ink)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 13, color: _Ui.muted)),
        ],
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  final int pct;
  const _ChangeBadge({required this.pct});

  @override
  Widget build(BuildContext context) {
    final up = pct >= 0;
    final color = up ? const Color(0xFF2E9E4F) : const Color(0xFFD32F2F);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        '${up ? '+' : ''}$pct%',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sales trend (smooth area line, last 7 days)
// ---------------------------------------------------------------------------

/// A round step (1, 2, 5 x 10^n) that gives roughly four gridlines.
double _niceInterval(double max) {
  if (max <= 0) return 1000;
  final rough = max / 4;
  final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  final n = rough / magnitude;
  final nice = n <= 1 ? 1.0 : (n <= 2 ? 2.0 : (n <= 5 ? 5.0 : 10.0));
  return nice * magnitude;
}

String _compactPeso(double v) {
  if (v >= 1000) {
    final k = v / 1000;
    return '₱${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}k';
  }
  return '₱${v.toStringAsFixed(0)}';
}

class _SalesTrendCard extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  const _SalesTrendCard({required this.trend});

  @override
  Widget build(BuildContext context) {
    const axisStyle = TextStyle(fontSize: 11, color: _Ui.muted);

    final values = trend.map((r) => _asNum(r['total_sales']).toDouble()).toList();
    final peak = values.isEmpty ? 0.0 : values.reduce(math.max);
    final interval = _niceInterval(peak);
    final maxY = math.max(interval * 2, ((peak * 1.05) / interval).ceil() * interval);
    final spots = [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])];

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle('Sales trend', subtitle: 'Last 7 days'),
          const SizedBox(height: 20),
          SizedBox(
            height: 240,
            child: spots.length < 2
                ? const Center(child: Text('Not enough data yet.', style: TextStyle(color: _Ui.muted)))
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (spots.length - 1).toDouble(),
                      minY: 0,
                      maxY: maxY,
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: interval,
                        getDrawingHorizontalLine: (_) => FlLine(color: _Ui.gridLine, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 48,
                            interval: interval,
                            getTitlesWidget: (value, meta) => Text(_compactPeso(value), style: axisStyle),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final i = value.round();
                              if ((value - i).abs() > 0.001 || i < 0 || i >= trend.length) {
                                return const SizedBox.shrink();
                              }
                              final day = DateTime.tryParse('${trend[i]['day']}');
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(day == null ? '' : DateFormat('E').format(day), style: axisStyle),
                              );
                            },
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touched) => touched
                              .map((s) => LineTooltipItem(
                                    '₱${_money.format(s.y)}',
                                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  ))
                              .toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          preventCurveOverShooting: true,
                          color: _Ui.tan,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: _Ui.tan.withOpacity(0.12)),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top selling items
// ---------------------------------------------------------------------------

class _TopSellingCard extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _TopSellingCard({required this.items});

  static const _rankColors = [_Ui.tan, _Ui.blue, _Ui.green, _Ui.amber, _Ui.red];

  @override
  Widget build(BuildContext context) {
    final maxSold = items.fold<num>(0, (m, i) {
      final sold = _asNum(i['total_sold']);
      return sold > m ? sold : m;
    });

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle('Top selling items', subtitle: 'Last 7 days'),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Text('Completed orders will show up here.', style: TextStyle(color: _Ui.muted))
          else
            for (var i = 0; i < items.length; i++) ...[
              _TopSellingRow(
                rank: i + 1,
                name: '${items[i]['food_name']}',
                sold: _asNum(items[i]['total_sold']),
                fraction: maxSold == 0 ? 0.0 : (_asNum(items[i]['total_sold']) / maxSold).toDouble(),
                color: _rankColors[i % _rankColors.length],
              ),
              if (i < items.length - 1) const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
}

class _TopSellingRow extends StatelessWidget {
  final int rank;
  final String name;
  final num sold;
  final double fraction;
  final Color color;
  const _TopSellingRow({
    required this.rank,
    required this.name,
    required this.sold,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withOpacity(0.16), borderRadius: BorderRadius.circular(7)),
              child: Text('$rank', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: _Ui.ink)),
            ),
            const SizedBox(width: 8),
            Text('${_money.format(sold)} sold', style: const TextStyle(fontSize: 13, color: _Ui.muted)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0).toDouble(),
            minHeight: 4,
            color: color,
            backgroundColor: color.withOpacity(0.15),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------

class _AlertStyle {
  final Color background;
  final Color dot;
  final Color title;
  const _AlertStyle(this.background, this.dot, this.title);
}

_AlertStyle _alertStyleFor(String severity) {
  switch (severity) {
    case 'critical':
      return const _AlertStyle(Color(0xFFFFEBEE), Color(0xFFF44336), Color(0xFFE53935));
    case 'warning':
      // Darker than the design's bright yellow so the title stays readable.
      return const _AlertStyle(Color(0xFFFFF8E1), Color(0xFFFFC107), Color(0xFF9A6A00));
    default:
      return const _AlertStyle(Color(0xFFE3F2FD), Color(0xFF2196F3), Color(0xFF1E88E5));
  }
}

class _AlertsCard extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;
  const _AlertsCard({required this.alerts});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle('Alerts'),
          const SizedBox(height: 16),
          if (alerts.isEmpty)
            const _AlertTile(severity: 'ok', title: 'All clear', message: 'Nothing needs your attention right now.')
          else
            for (var i = 0; i < alerts.length; i++) ...[
              _AlertTile(
                severity: '${alerts[i]['severity']}',
                title: '${alerts[i]['title']}',
                message: '${alerts[i]['message']}',
              ),
              if (i < alerts.length - 1) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final String severity;
  final String title;
  final String message;
  const _AlertTile({required this.severity, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final style = severity == 'ok'
        ? const _AlertStyle(Color(0xFFE8F5E9), Color(0xFF4CAF50), Color(0xFF2E7D32))
        : _alertStyleFor(severity);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: style.background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(width: 8, height: 8, decoration: BoxDecoration(color: style.dot, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: style.title)),
                const SizedBox(height: 2),
                Text(message, style: const TextStyle(fontSize: 12, color: _Ui.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Staff activity
// ---------------------------------------------------------------------------

String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0]).join().toUpperCase();
}

class _StaffActivityCard extends StatelessWidget {
  final List<Map<String, dynamic>> staff;
  final bool attendanceReady;
  const _StaffActivityCard({required this.staff, this.attendanceReady = true});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle('Staff activity'),
          if (!attendanceReady) ...[
            const SizedBox(height: 6),
            const Text(
              'Attendance is not set up on the server yet, so everyone shows as off duty.',
              style: TextStyle(fontSize: 12, color: _Ui.muted),
            ),
          ],
          const SizedBox(height: 16),
          if (staff.isEmpty)
            const Text('No active cashier or kitchen staff yet.', style: TextStyle(color: _Ui.muted))
          else
            for (var i = 0; i < staff.length; i++) ...[
              _StaffRow(member: staff[i]),
              if (i < staff.length - 1) const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
}

class _StaffRow extends StatelessWidget {
  final Map<String, dynamic> member;
  const _StaffRow({required this.member});

  @override
  Widget build(BuildContext context) {
    final name = '${member['name']}';
    final roleName = '${member['role_name']}';
    final presence = '${member['presence']}';

    final dotColor = presence == 'on_duty' ? _Ui.green : (presence == 'on_break' ? _Ui.amber : const Color(0xFFBDBDBD));
    final statusNote = presence == 'on_break' ? ' · On break' : (presence == 'off' ? ' · Off duty' : '');
    // Kitchen staff don't take orders, so they have no sales figures.
    final showSales = roleName != 'kitchen';

    return Row(
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        CircleAvatar(
          radius: 20,
          backgroundColor: _Ui.tanTint,
          child: Text(_initials(name), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _Ui.tanDeep)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: _Ui.ink)),
              Text('${_titleCase(roleName)}$statusNote', style: const TextStyle(fontSize: 12, color: _Ui.muted)),
            ],
          ),
        ),
        if (showSales)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₱${_money.format(_asNum(member['total_sales']))}', style: const TextStyle(fontSize: 14, color: _Ui.ink)),
              Text('${_asNum(member['order_count']).toInt()} orders', style: const TextStyle(fontSize: 12, color: _Ui.muted)),
            ],
          ),
      ],
    );
  }
}