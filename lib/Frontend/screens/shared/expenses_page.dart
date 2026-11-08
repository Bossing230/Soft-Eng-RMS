import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/models/expense.dart';
import 'package:rms/Frontend/repositories/expense_repository.dart';
import 'package:rms/Frontend/repositories/report_export_repository.dart';

const _border = Color(0xFFEBE3D8);
const _tanDeep = Color(0xFFB98A5E);
const _tanTint = Color(0xFFF0DFCF);
const _pillIdle = Color(0xFFEFE9E0);
const _fieldFill = Color(0xFFFBF5F0);
const _dialogBg = Color(0xFFF6E7DB);
const _ink = Color(0xFF2B2B2B);
const _muted = Color(0xFF7A7A7A);
const _red = Color(0xFFE53935);

/// Must match CATEGORIES in the backend expenseController.js.
const _categories = ['Ingredients', 'Utilities', 'Salaries', 'Rent', 'Equipment', 'Maintenance', 'Other'];

final _money = NumberFormat('#,##0.00');
String _peso(double v) => '₱${_money.format(v)}';

IconData _categoryIcon(String c) {
  switch (c) {
    case 'Ingredients':
      return Icons.shopping_basket_outlined;
    case 'Utilities':
      return Icons.bolt_outlined;
    case 'Salaries':
      return Icons.groups_outlined;
    case 'Rent':
      return Icons.home_work_outlined;
    case 'Equipment':
      return Icons.kitchen_outlined;
    case 'Maintenance':
      return Icons.build_outlined;
    default:
      return Icons.receipt_long_outlined;
  }
}

InputDecoration _decoration(String hint, {IconData? icon, String? error}) => InputDecoration(
      hintText: hint,
      errorText: error,
      prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _muted),
      filled: true,
      fillColor: _fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );

/// Expenses for Admin and Manager: record, edit, delete and download.
class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final _repo = ExpenseRepository();
  final _exportRepo = ReportExportRepository();
  final _day = DateFormat('yyyy-MM-dd');

  String _period = 'month'; // 'today' | 'week' | 'month' | 'all'
  ExpenseResult? _data;
  bool _loading = true;
  bool _refreshing = false; // a quiet reload (period change): the old list stays visible
  int _requestId = 0; // ignores answers to requests that were superseded
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({DateTime? start, DateTime? end}) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'today':
        return (start: today, end: today);
      case 'week':
        return (start: today.subtract(const Duration(days: 6)), end: today);
      case 'month':
        return (start: DateTime(now.year, now.month, 1), end: today);
      default:
        return (start: null, end: null);
    }
  }

    Future<void> _load({bool showSpinner = true}) async {
    final id = ++_requestId;
    setState(() {
      if (showSpinner) {
        _loading = true;
      } else {
        _refreshing = true;
      }
    });
    try {
      final r = _range;
      final data = await _repo.getAll(
        start: r.start == null ? null : _day.format(r.start!),
        end: r.end == null ? null : _day.format(r.end!),
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _data = data;
        _loading = false;
        _refreshing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      final hadData = _data != null;
      setState(() {
        _loading = false;
        _refreshing = false;
        if (!hadData) _error = e.toString();
      });
      if (hadData) _snack('Could not refresh: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setPeriod(String p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load(showSpinner: false);
  }

  Future<void> _openForm([Expense? existing]) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ExpenseDialog(existing: existing),
    );
    if (values == null) return;
    try {
      if (existing == null) {
        await _repo.create(
          category: values['category'],
          description: values['description'],
          amount: values['amount'],
          expenseDate: values['date'],
        );
      } else {
        await _repo.update(
          existing.expenseId,
          category: values['category'],
          description: values['description'],
          amount: values['amount'],
          expenseDate: values['date'],
        );
      }
      await _load(showSpinner: false);
      _snack(existing == null ? 'Expense recorded' : 'Expense saved');
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _delete(Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete this expense?', style: TextStyle(fontSize: 18)),
        content: Text('${e.description} · ${_peso(e.amount)}', style: const TextStyle(fontSize: 13.5, color: _muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.remove(e.expenseId);
      await _load(showSpinner: false);
      _snack('Expense deleted');
    } catch (err) {
      _snack('$err');
    }
  }

  Future<void> _download(String format) async {
    try {
      final r = _range;
      final started = await _exportRepo.download(report: 'expenses', format: format, start: r.start, end: r.end);
      _snack(started ? 'Downloading the expense report…' : "Downloading isn't supported on this device yet.");
    } catch (e) {
      _snack('Could not download the report: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final data = _data;
    if (_error != null && data == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: _muted),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }

    final top = (data != null && data.byCategory.isNotEmpty) ? data.byCategory.first : null;
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(color: _tanDeep, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.receipt_long_outlined, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Expenses', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _ink)),
                          Text('Money spent running the restaurant', style: TextStyle(fontSize: 12, color: _muted)),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Download report',
                      icon: const Icon(Icons.download_outlined, color: _tanDeep),
                      onSelected: _download,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'pdf', child: Text('Download PDF')),
                        PopupMenuItem(value: 'excel', child: Text('Download Excel')),
                        PopupMenuItem(value: 'csv', child: Text('Download CSV')),
                      ],
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Expense'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _tanDeep,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: const {'today': 'Today', 'week': 'Last 7 days', 'month': 'This month', 'all': 'All time'}
                      .entries
                      .map((e) => _PeriodPill(label: e.value, selected: e.key == _period, onTap: () => _setPeriod(e.key)))
                      .toList(),
                ),
                const SizedBox(height: 16),
                if (data != null)
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _StatCard(label: 'Total expenses', value: _peso(data.total), icon: Icons.payments_outlined),
                      _StatCard(label: 'Entries', value: '${data.count}', icon: Icons.format_list_numbered),
                      _StatCard(
                        label: 'Biggest category',
                        value: top == null ? '-' : top.category,
                        sublabel: top == null ? null : _peso(top.total),
                        icon: Icons.pie_chart_outline,
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                if (data == null || data.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('No expenses in this period.', style: TextStyle(color: _muted))),
                  )
                else
                  for (final e in data.items) _ExpenseRow(expense: e, onEdit: () => _openForm(e), onDelete: () => _delete(e)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PeriodPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _tanDeep : _pillIdle,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? Colors.white : _muted),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sublabel;
  final IconData icon;
  const _StatCard({required this.label, required this.value, required this.icon, this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: _tanTint, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: _tanDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _ink)),
                ),
                Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
                if (sublabel != null) Text(sublabel!, style: const TextStyle(fontSize: 11, color: _tanDeep)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ExpenseRow({required this.expense, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(expense.date);
    final dateText = parsed == null ? expense.date : DateFormat('MMM d, yyyy').format(parsed);
    final subtitle = [expense.category, dateText, if (expense.recordedBy.isNotEmpty) expense.recordedBy].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: _tanTint, borderRadius: BorderRadius.circular(10)),
            child: Icon(_categoryIcon(expense.category), size: 20, color: _tanDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _ink)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_peso(expense.amount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: _muted),
            onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpenseDialog extends StatefulWidget {
  final Expense? existing;
  const _ExpenseDialog({this.existing});

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  late final _description = TextEditingController(text: widget.existing?.description ?? '');
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : widget.existing!.amount.toStringAsFixed(2),
  );
  late String? _category = widget.existing?.category;
  late DateTime _date = DateTime.tryParse(widget.existing?.date ?? '') ?? DateTime.now();

  String? _categoryError;
  String? _descriptionError;
  String? _amountError;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final description = _description.text.trim();
    final amount = double.tryParse(_amount.text.trim());
    setState(() {
      _categoryError = _category == null ? 'Choose a category' : null;
      _descriptionError = description.isEmpty ? 'Enter a description' : null;
      _amountError = (amount == null || amount <= 0) ? 'Enter an amount above zero' : null;
    });
    if (_categoryError != null || _descriptionError != null || _amountError != null) return;
    Navigator.of(context).pop({
      'category': _category,
      'description': description,
      'amount': (amount! * 100).roundToDouble() / 100,
      'date': DateFormat('yyyy-MM-dd').format(_date),
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget gap() => const SizedBox(height: 12);
    return AlertDialog(
      backgroundColor: _dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.existing == null ? 'Add expense' : 'Edit expense', style: const TextStyle(fontSize: 18)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                hint: const Text('Category', style: TextStyle(color: _muted)),
                decoration: _decoration('', error: _categoryError),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() {
                  _category = v;
                  _categoryError = null;
                }),
              ),
              gap(),
              TextField(controller: _description, decoration: _decoration('Description, e.g. Chicken delivery', icon: Icons.notes_outlined, error: _descriptionError)),
              gap(),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _decoration('Amount (₱)', icon: Icons.payments_outlined, error: _amountError),
              ),
              gap(),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: _decoration('', icon: Icons.event_outlined),
                  child: Text(DateFormat('MMM d, yyyy').format(_date), style: const TextStyle(fontSize: 14, color: _ink)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _tanDeep, foregroundColor: Colors.white),
          onPressed: _submit,
          child: Text(widget.existing == null ? 'Add expense' : 'Save'),
        ),
      ],
    );
  }
}