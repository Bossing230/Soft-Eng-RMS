import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/repositories/report_export_repository.dart';

const _border = Color(0xFFEBE3D8);
const _tanDeep = Color(0xFFB98A5E);
const _ink = Color(0xFF2B2B2B);
const _muted = Color(0xFF7A7A7A);

/// "Download reports" card for the Reports page: sales, inventory and
/// expense reports as PDF, Excel or CSV, for the Daily, Weekly or Monthly
/// period (or a custom range).
class ReportExportPanel extends StatefulWidget {
  /// The period selected on the Reports page: 'daily' | 'weekly' | 'monthly'.
  final String period;
  const ReportExportPanel({super.key, this.period = 'weekly'});

  @override
  State<ReportExportPanel> createState() => _ReportExportPanelState();
}

class _ReportExportPanelState extends State<ReportExportPanel> {
  final _repo = ReportExportRepository();
  final _day = DateFormat('MMM d, yyyy');

  late String _scope = widget.period; // 'daily' | 'weekly' | 'monthly' | 'custom'
  DateTimeRange? _custom;
  String _format = 'pdf';
  String? _busy; // which report is downloading right now

  @override
  void didUpdateWidget(covariant ReportExportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the Daily / Weekly / Monthly buttons of the page.
    if (oldWidget.period != widget.period) _scope = widget.period;
  }

  DateTimeRange get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_scope) {
      case 'daily':
        return DateTimeRange(start: today, end: today);
      case 'monthly':
        return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
      case 'custom':
        return _custom ?? DateTimeRange(start: today, end: today);
      default:
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
    }
  }

  String get _rangeText {
    final r = _range;
    if (r.start == r.end) return _day.format(r.start);
    return '${_day.format(r.start)} – ${_day.format(r.end)}';
  }

  Future<void> _pickCustom() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _custom,
    );
    if (picked != null) {
      setState(() {
        _custom = picked;
        _scope = 'custom';
      });
    }
  }

  Future<void> _download(String report, {bool dated = true}) async {
    if (_busy != null) return;
    setState(() => _busy = report);
    try {
      final r = _range;
      final started = await _repo.download(
        report: report,
        format: _format,
        start: dated ? r.start : null,
        end: dated ? r.end : null,
      );
      _snack(started ? 'Downloading the $report report…' : "Downloading isn't supported on this device yet.");
    } catch (e) {
      _snack('Could not download the report: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Download reports', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: _ink)),
          const SizedBox(height: 2),
          Text('Period: $_rangeText', style: const TextStyle(fontSize: 13, color: _muted)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'daily', label: Text('Daily')),
                  ButtonSegment(value: 'weekly', label: Text('Weekly')),
                  ButtonSegment(value: 'monthly', label: Text('Monthly')),
                  ButtonSegment(value: 'custom', label: Text('Custom')),
                ],
                selected: {_scope},
                onSelectionChanged: (s) {
                  final next = s.first;
                  if (next == 'custom') {
                    _pickCustom();
                  } else {
                    setState(() => _scope = next);
                  }
                },
              ),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'pdf', label: Text('PDF')),
                  ButtonSegment(value: 'excel', label: Text('Excel')),
                  ButtonSegment(value: 'csv', label: Text('CSV')),
                ],
                selected: {_format},
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _tile('sales', 'Sales report', 'Orders and sales per day, with expenses and the difference.', Icons.payments_outlined),
          _tile('inventory', 'Inventory report', 'Current stock of every ingredient (not affected by the period).',
              Icons.inventory_2_outlined,
              dated: false),
          _tile('expenses', 'Expense report', 'Every recorded expense in the period.', Icons.receipt_long_outlined),
        ],
      ),
    );
  }

  Widget _tile(String report, String title, String subtitle, IconData icon, {bool dated = true}) {
    final busy = _busy == report;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF5F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: _tanDeep),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: _muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _busy != null ? null : () => _download(report, dated: dated),
              icon: busy
                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_outlined, size: 18),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _tanDeep,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}