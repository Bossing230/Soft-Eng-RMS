import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rms/Frontend/services/api_services.dart';

import '../../repositories/table_repository.dart';
import '../cashier/pos_page.dart';

// ---------------------------------------------------------------------------
// Design tokens, taken from the Tables design.
// ---------------------------------------------------------------------------
class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const tanDeep = Color(0xFFB98A5E);
  static const pillIdle = Color(0xFFEFE9E0);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
}

class _StatusStyle {
  final Color card; // card tint
  final Color border; // card border
  final Color text; // dot, label, table number
  final String label;
  const _StatusStyle(this.card, this.border, this.text, this.label);
}

const _statusOrder = ['available', 'occupied', 'reserved', 'cleaning'];

_StatusStyle _styleFor(String status) {
  switch (status) {
    case 'available':
      return const _StatusStyle(Color(0xFFEAF6EC), Color(0xFFBFE2C4), Color(0xFF2E7D32), 'Available');
    case 'occupied':
      return const _StatusStyle(Color(0xFFFCEAEA), Color(0xFFF2BDBD), Color(0xFFD32F2F), 'Occupied');
    case 'reserved':
      return const _StatusStyle(Color(0xFFFBF2DE), Color(0xFFEAD9A8), Color(0xFFB07A00), 'Reserved');
    case 'cleaning':
      return const _StatusStyle(Color(0xFFE6F0FA), Color(0xFFB9D4EE), Color(0xFF1E6FBF), 'Cleaning');
    default:
      return _StatusStyle(_Ui.pillIdle, _Ui.border, _Ui.muted, status);
  }
}

String _titleCase(String s) => s.isEmpty ? s : (s[0].toUpperCase() + s.substring(1));

/// "Indoor" or "Outdoor" for a table row (anything else, or empty, counts as indoor).
String _locationLabel(dynamic location) {
  final value = '${location ?? ''}'.trim().toLowerCase();
  return _titleCase(value == 'outdoor' ? 'outdoor' : 'indoor');
}

/// Tables board for Manager, Admin and Cashier: every table as a card,
/// colored by status, with its seats, indoor/outdoor and who is currently
/// seated there when known. Tapping a card opens a sheet to change its status
/// or start a new order.
///
/// With [canManage] (managers and administrators) the page also shows an
/// "Add table" button, and the sheet gets an "Edit table" button to change a
/// table's number, seats and indoor/outdoor. The server enforces the same rule
/// (see tableRoutes.js), so cashiers cannot add or edit tables either way.
class TablesManagementPage extends StatefulWidget {
  final bool canManage;
  const TablesManagementPage({super.key, this.canManage = false});

  @override
  State<TablesManagementPage> createState() => _TablesManagementPageState();
}

class _TablesManagementPageState extends State<TablesManagementPage> {
  final _repo = TableRepository();
  Timer? _timer;
  List<Map<String, dynamic>> _tables = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(showSpinner: false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
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
        _tables = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_tables.isEmpty) _error = '$e';
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  int _count(String status) => _tables.where((t) => t['status'] == status).length;

  // ---- add / edit ----

  Future<void> _addTable() async {
    final result = await showDialog<_TableFormResult>(
      context: context,
      builder: (_) => const _TableFormDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await _repo.create(
        tableNumber: result.tableNumber,
        capacity: result.capacity,
        location: result.location,
      );
      await _load(showSpinner: false);
      _snack('Table ${result.tableNumber} added.');
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not add the table: $e');
    }
  }

  Future<void> _editTable(Map<String, dynamic> table) async {
    final result = await showDialog<_TableFormResult>(
      context: context,
      builder: (_) => _TableFormDialog(table: table),
    );
    if (result == null || !mounted) return;
    try {
      await _repo.update(
        table['table_id'] as int,
        tableNumber: result.tableNumber,
        capacity: result.capacity,
        location: result.location,
      );
      await _load(showSpinner: false);
      _snack('Table ${result.tableNumber} updated.');
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not update the table: $e');
    }
  }

  // ---- open a table ----

  Future<void> _openTable(Map<String, dynamic> table) async {
    final action = await showModalBottomSheet<_TableSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TableDetailSheet(table: table, canManage: widget.canManage),
    );
    if (action == null || !mounted) return;

    if (action.edit) {
      await _editTable(table);
      return;
    }

    if (action.newOrder) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text('New order — Table ${table['table_number']}')),
            body: PosPage(initialTableId: table['table_id'] as int, initialTableNumber: '${table['table_number']}'),
          ),
        ),
      );
      _load(showSpinner: false);
      return;
    }

    if (action.status != null) {
      try {
        await _repo.setStatus(table['table_id'] as int, action.status!);
        await _load(showSpinner: false);
        _snack('Table ${table['table_number']} marked ${action.status}.');
      } catch (e) {
        _snack('$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _tables.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40, color: _Ui.muted),
              const SizedBox(height: 12),
              const Text("Couldn't load the tables", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _Ui.muted)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(wide ? 24 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _SummaryBadge(label: '${_tables.length} total', color: _Ui.muted),
                          for (final status in _statusOrder)
                            if (status != 'cleaning' || _count(status) > 0)
                              _SummaryBadge(label: '${_count(status)} $status', color: _styleFor(status).text),
                        ],
                      ),
                    ),
                    if (widget.canManage) ...[
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _addTable,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add table'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _Ui.tanDeep,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                if (_tables.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        widget.canManage ? 'No tables yet. Tap "Add table" to create one.' : 'No tables yet.',
                        style: const TextStyle(color: _Ui.muted),
                      ),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 230,
                      mainAxisExtent: 160,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: _tables.length,
                    itemBuilder: (_, i) {
                      final table = _tables[i];
                      return _TableCard(table: table, onTap: () => _openTable(table));
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SummaryBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: _Ui.pillIdle, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ---------------------------------------------------------------------------
// Table card
// ---------------------------------------------------------------------------

class _TableCard extends StatelessWidget {
  final Map<String, dynamic> table;
  final VoidCallback onTap;
  const _TableCard({required this.table, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = '${table['status']}';
    final style = _styleFor(status);
    final name = (table['customer_name'] as String?)?.trim();

    return Material(
      color: style.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: style.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${table['table_number']}',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: style.text),
                  ),
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: style.text, shape: BoxShape.circle)),
                ],
              ),
              const Spacer(),
              Text(
                style.label.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: style.text, letterSpacing: 0.3),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.people_outline, size: 14, color: _Ui.muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${table['capacity']} seats · ${_locationLabel(table['location'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _Ui.muted),
                    ),
                  ),
                ],
              ),
              if (name != null && name.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: style.text)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit table form
// ---------------------------------------------------------------------------

class _TableFormResult {
  final String tableNumber;
  final int capacity;
  final String location; // indoor | outdoor
  const _TableFormResult(this.tableNumber, this.capacity, this.location);
}

class _TableFormDialog extends StatefulWidget {
  /// The table being edited, or null to add a new one.
  final Map<String, dynamic>? table;
  const _TableFormDialog({this.table});

  @override
  State<_TableFormDialog> createState() => _TableFormDialogState();
}

class _TableFormDialogState extends State<_TableFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _seats;
  late String _location;

  bool get _editing => widget.table != null;

  @override
  void initState() {
    super.initState();
    final t = widget.table;
    _number = TextEditingController(text: t == null ? '' : '${t['table_number']}');
    _seats = TextEditingController(text: t == null ? '' : '${t['capacity']}');
    final loc = '${t?['location'] ?? 'indoor'}'.trim().toLowerCase();
    _location = loc == 'outdoor' ? 'outdoor' : 'indoor';
  }

  @override
  void dispose() {
    _number.dispose();
    _seats.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _TableFormResult(_number.text.trim(), int.parse(_seats.text.trim()), _location),
    );
  }

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFFBF5F0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit table' : 'Add table'),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _number,
                autofocus: !_editing,
                textCapitalization: TextCapitalization.characters,
                decoration: _decoration('Table number', hint: 'e.g. T7'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a table number' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _seats,
                keyboardType: TextInputType.number,
                decoration: _decoration('Seats', hint: 'e.g. 4'),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n < 1) return 'Enter 1 or more seats';
                  if (n > 99) return 'That is too many seats';
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              const Text('Location', style: TextStyle(fontSize: 13, color: _Ui.muted)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'indoor', label: Text('Indoor'), icon: Icon(Icons.meeting_room_outlined, size: 18)),
                    ButtonSegment(value: 'outdoor', label: Text('Outdoor'), icon: Icon(Icons.deck_outlined, size: 18)),
                  ],
                  selected: {_location},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _location = s.first),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _Ui.tanDeep,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(_editing ? 'Save' : 'Add table'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Table detail sheet
// ---------------------------------------------------------------------------

class _TableSheetResult {
  final String? status;
  final bool newOrder;
  final bool edit;
  const _TableSheetResult.status(this.status)
      : newOrder = false,
        edit = false;
  const _TableSheetResult.newOrder()
      : status = null,
        newOrder = true,
        edit = false;
  const _TableSheetResult.edit()
      : status = null,
        newOrder = false,
        edit = true;
}

class _TableDetailSheet extends StatelessWidget {
  final Map<String, dynamic> table;
  final bool canManage;
  const _TableDetailSheet({required this.table, required this.canManage});

  @override
  Widget build(BuildContext context) {
    final status = '${table['status']}';
    final style = _styleFor(status);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _Ui.border, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Table ${table['table_number']}',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: _Ui.ink),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: style.card, borderRadius: BorderRadius.circular(20)),
                  child: Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: style.text)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${table['capacity']} seats · ${_locationLabel(table['location'])}',
              style: const TextStyle(fontSize: 13, color: _Ui.muted),
            ),
            const SizedBox(height: 22),
            const Text('Change status', style: TextStyle(fontSize: 13, color: _Ui.muted)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _statusOrder)
                  _StatusOptionButton(
                    status: s,
                    selected: s == status,
                    onTap: () => Navigator.of(context).pop(_TableSheetResult.status(s)),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(const _TableSheetResult.newOrder()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New order for this table'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Ui.tanDeep,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (canManage) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(const _TableSheetResult.edit()),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit table'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _Ui.tanDeep,
                    side: const BorderSide(color: _Ui.tanDeep),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusOptionButton extends StatelessWidget {
  final String status;
  final bool selected;
  final VoidCallback onTap;
  const _StatusOptionButton({required this.status, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(status);
    return OutlinedButton(
      onPressed: selected ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? style.text : _Ui.ink,
        backgroundColor: selected ? style.card : Colors.white,
        side: BorderSide(color: selected ? style.text : _Ui.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(status, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
    );
  }
}