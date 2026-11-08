import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/repositories/report_export_repository.dart';

const _tanDeep = Color(0xFFB98A5E);
const _tanTint = Color(0xFFF0DFCF);
const _border = Color(0xFFEBE3D8);
const _fieldFill = Color(0xFFFBF5F0);
const _dialogBg = Color(0xFFF6E7DB);
const _ink = Color(0xFF2B2B2B);
const _muted = Color(0xFF7A7A7A);

class _SalesReportChoice {
  final String format; // 'pdf' | 'excel' | 'csv'
  final DateTime start;
  final DateTime end;
  const _SalesReportChoice(this.format, this.start, this.end);

  String get formatLabel => format == 'excel' ? 'Excel' : format.toUpperCase();
}

/// Opens the "Download report" dialog for the sales report, then downloads it.
/// [period] is the one selected on the Reports page ('daily', 'weekly' or
/// 'monthly'); the dialog opens on it.
Future<void> showSalesReportDialog(BuildContext context, {String period = 'weekly'}) async {
  final scope = period == 'daily' ? 'today' : (period == 'monthly' ? 'month' : 'week');
  final choice = await showDialog<_SalesReportChoice>(
    context: context,
    builder: (_) => _SalesReportDialog(initialScope: scope),
  );
  if (choice == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final started = await ReportExportRepository().download(
      report: 'sales',
      format: choice.format,
      start: choice.start,
      end: choice.end,
    );
    messenger.showSnackBar(SnackBar(
      content: Text(started ? 'Downloading the ${choice.formatLabel} sales report…' : "Downloading isn't supported on this device yet."),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not download the report: $e')));
  }
}

class _SalesReportDialog extends StatefulWidget {
  final String initialScope; // 'today' | 'week' | 'month'
  const _SalesReportDialog({required this.initialScope});

  @override
  State<_SalesReportDialog> createState() => _SalesReportDialogState();
}

class _SalesReportDialogState extends State<_SalesReportDialog> {
  final _day = DateFormat('MMM d, yyyy');
  final _short = DateFormat('MMM d');

  String _format = 'pdf';
  late String _scope = widget.initialScope; // 'today' | 'week' | 'month' | 'custom'
  DateTimeRange? _custom;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTimeRange get _range {
    switch (_scope) {
      case 'today':
        return DateTimeRange(start: _today, end: _today);
      case 'month':
        return DateTimeRange(start: _today.subtract(const Duration(days: 29)), end: _today);
      case 'custom':
        return _custom ?? DateTimeRange(start: _today, end: _today);
      default:
        return DateTimeRange(start: _today.subtract(const Duration(days: 6)), end: _today);
    }
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

  @override
  Widget build(BuildContext context) {
    const heading = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _muted);
    final week = _today.subtract(const Duration(days: 6));
    final month = _today.subtract(const Duration(days: 29));

    return AlertDialog(
      backgroundColor: _dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Download sales report', style: TextStyle(fontSize: 18)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('FORMAT', style: heading),
              const SizedBox(height: 8),
              _OptionTile(
                icon: Icons.picture_as_pdf_outlined,
                title: 'PDF',
                subtitle: 'Easy to print or share',
                selected: _format == 'pdf',
                onTap: () => setState(() => _format = 'pdf'),
              ),
              _OptionTile(
                icon: Icons.table_chart_outlined,
                title: 'Excel (.xlsx)',
                subtitle: 'Formatted, with filters you can sort',
                selected: _format == 'excel',
                onTap: () => setState(() => _format = 'excel'),
              ),
              _OptionTile(
                icon: Icons.description_outlined,
                title: 'CSV',
                subtitle: 'Plain data for other programs',
                selected: _format == 'csv',
                onTap: () => setState(() => _format = 'csv'),
              ),
              const SizedBox(height: 14),
              const Text('PERIOD', style: heading),
              const SizedBox(height: 8),
              _OptionTile(
                icon: Icons.today_outlined,
                title: 'Daily',
                subtitle: 'Today, ${_day.format(_today)}',
                selected: _scope == 'today',
                onTap: () => setState(() => _scope = 'today'),
              ),
              _OptionTile(
                icon: Icons.view_week_outlined,
                title: 'Weekly',
                subtitle: 'Last 7 days: ${_short.format(week)} – ${_day.format(_today)}',
                selected: _scope == 'week',
                onTap: () => setState(() => _scope = 'week'),
              ),
              _OptionTile(
                icon: Icons.calendar_month_outlined,
                title: 'Monthly',
                subtitle: 'Last 30 days: ${_short.format(month)} – ${_day.format(_today)}',
                selected: _scope == 'month',
                onTap: () => setState(() => _scope = 'month'),
              ),
              _OptionTile(
                icon: Icons.date_range_outlined,
                title: 'Custom range',
                subtitle: _custom == null ? 'Pick the start and end dates' : '${_day.format(_custom!.start)} – ${_day.format(_custom!.end)}',
                selected: _scope == 'custom',
                onTap: _pickCustom,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _tanDeep, foregroundColor: Colors.white),
          onPressed: () {
            final r = _range;
            Navigator.of(context).pop(_SalesReportChoice(_format, r.start, r.end));
          },
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('Download'),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? _tanTint : _fieldFill,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? _tanDeep : _border),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: selected ? _tanDeep : _muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
                      Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _muted)),
                    ],
                  ),
                ),
                if (selected) const Icon(Icons.check_circle, size: 20, color: _tanDeep),
              ],
            ),
          ),
        ),
      ),
    );
  }
}