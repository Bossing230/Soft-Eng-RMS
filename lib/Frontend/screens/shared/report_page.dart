import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../repositories/dashboard_repository.dart';

// ---------------------------------------------------------------------------
// Design tokens, taken from the reports design.
// ---------------------------------------------------------------------------
class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const gridLine = Color(0xFFEFE8DE);
  static const tan = Color(0xFFD4A574);
  static const tanDeep = Color(0xFFB98A5E);
  static const tanTint = Color(0xFFF0DFCF);
  static const pillIdle = Color(0xFFEFE9E0);
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
// Buckets: one entry per hour (daily) or per day (weekly / monthly)
// ---------------------------------------------------------------------------
class _Bucket {
  /// 'YYYY-MM-DD' for days, the hour number as text for hours.
  final String key;
  final double revenue;
  final int orders;
  const _Bucket(this.key, this.revenue, this.orders);

  factory _Bucket.fromJson(Map<String, dynamic> j) =>
      _Bucket('${j['key']}', _asNum(j['revenue']).toDouble(), _asNum(j['orders']).toInt());

  int get hour => int.tryParse(key) ?? 0;
}

String _hourShort(int h) => h == 0 ? '12a' : (h < 12 ? '${h}a' : (h == 12 ? '12p' : '${h - 12}p'));
String _hourLong(int h) => h == 0 ? '12 AM' : (h < 12 ? '$h AM' : (h == 12 ? '12 PM' : '${h - 12} PM'));

String _axisLabel(_Bucket b, String type, String period) {
  if (type == 'hour') return _hourShort(b.hour);
  final d = DateTime.tryParse(b.key);
  if (d == null) return '';
  return period == 'weekly' ? DateFormat('E').format(d) : DateFormat('d').format(d);
}

String _tooltipLabel(_Bucket b, String type) {
  if (type == 'hour') return _hourLong(b.hour);
  final d = DateTime.tryParse(b.key);
  return d == null ? '' : DateFormat('EEE, MMM d').format(d);
}

/// Which x-axis labels to draw, so the axis never gets crowded.
bool _showAxisLabel(int i, int count, String type) {
  if (type == 'hour') return i % 2 == 0;
  if (count <= 7) return true;
  return i % 5 == 0 || i == count - 1;
}

/// Daily view: hide the quiet hours at both ends (but keep 8 AM to 8 PM).
List<_Bucket> _visibleBuckets(List<_Bucket> all, String type) {
  if (type != 'hour') return all;
  var first = 8;
  var last = 20;
  for (final b in all) {
    if (b.revenue > 0 || b.orders > 0) {
      if (b.hour < first) first = b.hour;
      if (b.hour > last) last = b.hour;
    }
  }
  return all.where((b) => b.hour >= first && b.hour <= last).toList();
}

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

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Reports for Admin and Manager: Daily / Weekly / Monthly summary cards,
/// revenue and order-volume charts, and top selling items, all from
/// `GET /reports/analytics?period=...`.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _repo = DashboardRepository();
  String _period = 'weekly'; // 'daily' | 'weekly' | 'monthly'
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  int _requestId = 0; // ignores answers to requests that were superseded

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    final id = ++_requestId;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _repo.getReportsAnalytics(period: _period);
      if (!mounted || id != _requestId) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      if (showSpinner || _data == null) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not refresh: $e')));
      }
    }
  }

  void _setPeriod(String period) {
    if (period == _period) return;
    setState(() => _period = period);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: _PeriodPills(selected: _period, onChanged: _setPeriod),
                    ),
                    const SizedBox(height: 16),
                    _content(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const SizedBox(height: 320, child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _data == null) {
      return SizedBox(
        height: 320,
        child: _ErrorView(
          message: _error ?? 'Something went wrong.',
          onRetry: _load,
        ),
      );
    }

    final d = _data!;
    final type = '${d['bucketType']}';
    final summary = _asMap(d['summary']);
    final best = d['best'] is Map ? _asMap(d['best']) : null;
    final all = _asList(d['buckets']).map(_Bucket.fromJson).toList();
    final visible = _visibleBuckets(all, type);
    final hasSales = _asNum(summary['orders']) > 0;

    return Column(
      children: [
        _StatCards(summary: summary, best: best, type: type, period: _period),
        const SizedBox(height: 16),
        _RevenuePanel(
          buckets: visible,
          type: type,
          period: _period,
          bestKey: best == null ? null : '${best['key']}',
          hasSales: hasSales,
        ),
        const SizedBox(height: 16),
        _VolumePanel(buckets: visible, type: type, period: _period, hasSales: hasSales),
        const SizedBox(height: 16),
        _TopItemsPanel(items: _asList(d['topItems']), period: _period),
      ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40, color: _Ui.muted),
          const SizedBox(height: 12),
          const Text("Couldn't load the report", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _Ui.muted)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final String message;
  const _EmptyChart(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message, style: const TextStyle(color: _Ui.muted)));
  }
}

// ---------------------------------------------------------------------------
// Daily / Weekly / Monthly pills
// ---------------------------------------------------------------------------

class _PeriodPills extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _PeriodPills({required this.selected, required this.onChanged});

  static const _labels = {'daily': 'Daily', 'weekly': 'Weekly', 'monthly': 'Monthly'};

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: _labels.entries.map((e) {
        final isSelected = e.key == selected;
        return Material(
          color: isSelected ? _Ui.tanDeep : _Ui.pillIdle,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onChanged(e.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              child: Text(
                e.value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : _Ui.muted,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat cards
// ---------------------------------------------------------------------------

class _StatCards extends StatelessWidget {
  final Map<String, dynamic> summary;
  final Map<String, dynamic>? best;
  final String type;
  final String period;
  const _StatCards({required this.summary, required this.best, required this.type, required this.period});

  String _bestValue() {
    if (best == null) return '—';
    final key = '${best!['key']}';
    if (type == 'hour') return _hourLong(int.tryParse(key) ?? 0);
    final d = DateTime.tryParse(key);
    if (d == null) return '—';
    return period == 'weekly' ? DateFormat('EEEE').format(d) : DateFormat('MMM d').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final change = summary['revenueChangePct'];

    final cards = <Widget>[
      _StatCard(
        icon: Icons.payments_outlined,
        color: _Ui.tanDeep,
        value: '₱${_money.format(_asNum(summary['revenue']))}',
        label: 'Total revenue',
        changePct: change is num ? change.round() : null,
      ),
      _StatCard(
        icon: Icons.receipt_long_outlined,
        color: _Ui.blue,
        value: _money.format(_asNum(summary['orders'])),
        label: 'Total orders',
      ),
      _StatCard(
        icon: Icons.trending_up,
        color: _Ui.green,
        value: '₱${_money.format(_asNum(summary['avgOrderValue']))}',
        label: 'Avg. order value',
      ),
      _StatCard(
        icon: Icons.star_outline,
        color: _Ui.amber,
        value: _bestValue(),
        label: type == 'hour' ? 'Best hour' : 'Best day',
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
// Revenue overview (bars, best one highlighted)
// ---------------------------------------------------------------------------

const _axisStyle = TextStyle(fontSize: 11, color: _Ui.muted);

class _RevenuePanel extends StatelessWidget {
  final List<_Bucket> buckets;
  final String type;
  final String period;
  final String? bestKey;
  final bool hasSales;
  const _RevenuePanel({
    required this.buckets,
    required this.type,
    required this.period,
    required this.bestKey,
    required this.hasSales,
  });

  @override
  Widget build(BuildContext context) {
    final peak = buckets.fold<double>(0, (m, b) => b.revenue > m ? b.revenue : m);
    final interval = _niceInterval(peak);
    final maxY = math.max(interval * 2, ((peak * 1.05) / interval).ceil() * interval);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle('Revenue overview', subtitle: type == 'hour' ? 'Sales per hour' : 'Sales per day'),
          const SizedBox(height: 20),
          SizedBox(
            height: 260,
            child: !hasSales || buckets.isEmpty
                ? const _EmptyChart('No completed sales in this period yet.')
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final barWidth = ((constraints.maxWidth - 56) / buckets.length * 0.55).clamp(4.0, 28.0).toDouble();
                      return BarChart(
                        BarChartData(
                          minY: 0,
                          maxY: maxY,
                          alignment: BarChartAlignment.spaceAround,
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
                                getTitlesWidget: (value, meta) => Text(_compactPeso(value), style: _axisStyle),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                interval: 1,
                                getTitlesWidget: (value, meta) {
                                  final i = value.round();
                                  if (i < 0 || i >= buckets.length || !_showAxisLabel(i, buckets.length, type)) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(_axisLabel(buckets[i], type, period), style: _axisStyle),
                                  );
                                },
                              ),
                            ),
                          ),
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                                '${_tooltipLabel(buckets[group.x], type)}\n₱${_money.format(rod.toY)}',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                            ),
                          ),
                          barGroups: [
                            for (var i = 0; i < buckets.length; i++)
                              BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: buckets[i].revenue,
                                    width: barWidth,
                                    color: buckets[i].key == bestKey ? _Ui.tan : _Ui.tanTint,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order volume (smooth green area line)
// ---------------------------------------------------------------------------

class _VolumePanel extends StatelessWidget {
  final List<_Bucket> buckets;
  final String type;
  final String period;
  final bool hasSales;
  const _VolumePanel({required this.buckets, required this.type, required this.period, required this.hasSales});

  @override
  Widget build(BuildContext context) {
    final values = buckets.map((b) => b.orders.toDouble()).toList();
    final peak = values.isEmpty ? 0.0 : values.reduce(math.max);
    // Whole-number gridlines: an order count can't be 0.5.
    final interval = math.max(1.0, _niceInterval(peak));
    final maxY = math.max(interval * 2, ((peak * 1.05) / interval).ceil() * interval);
    final spots = [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])];

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle('Order volume', subtitle: type == 'hour' ? 'Orders per hour' : 'Orders per day'),
          const SizedBox(height: 20),
          SizedBox(
            height: 240,
            child: !hasSales || spots.length < 2
                ? const _EmptyChart('No completed orders in this period yet.')
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
                            reservedSize: 36,
                            interval: interval,
                            getTitlesWidget: (value, meta) => Text('${value.round()}', style: _axisStyle),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final i = value.round();
                              if ((value - i).abs() > 0.001 ||
                                  i < 0 ||
                                  i >= buckets.length ||
                                  !_showAxisLabel(i, buckets.length, type)) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(_axisLabel(buckets[i], type, period), style: _axisStyle),
                              );
                            },
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touched) => touched.map((s) {
                            final i = s.x.round().clamp(0, buckets.length - 1).toInt();
                            final orders = s.y.toInt();
                            return LineTooltipItem(
                              '${_tooltipLabel(buckets[i], type)}\n$orders ${orders == 1 ? 'order' : 'orders'}',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                            );
                          }).toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          preventCurveOverShooting: true,
                          color: _Ui.green,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: _Ui.green.withOpacity(0.10)),
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

class _TopItemsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String period;
  const _TopItemsPanel({required this.items, required this.period});

  static const _rankColors = [_Ui.tan, _Ui.blue, _Ui.green, _Ui.amber, _Ui.red];

  String get _subtitle => period == 'daily' ? 'Today' : (period == 'weekly' ? 'Last 7 days' : 'Last 30 days');

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
          _PanelTitle('Top selling items', subtitle: _subtitle),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Text('Completed orders will show up here.', style: TextStyle(color: _Ui.muted))
          else
            for (var i = 0; i < items.length; i++) ...[
              _TopItemRow(
                rank: i + 1,
                name: '${items[i]['food_name']}',
                sold: _asNum(items[i]['total_sold']),
                revenue: _asNum(items[i]['total_revenue']),
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

class _TopItemRow extends StatelessWidget {
  final int rank;
  final String name;
  final num sold;
  final num revenue;
  final double fraction;
  final Color color;
  const _TopItemRow({
    required this.rank,
    required this.name,
    required this.sold,
    required this.revenue,
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
            const SizedBox(width: 12),
            Text('₱${_money.format(revenue)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _Ui.ink)),
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