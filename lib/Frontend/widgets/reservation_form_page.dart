import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/models/reservations.dart';
import 'package:rms/Frontend/repositories/reservation_repository.dart';

class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const tan = Color(0xFFD4A574);
  static const tanDeep = Color(0xFFB98A5E);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
  static const red = Color(0xFFD32F2F);
}

const _maxGuests = 30;

/// A full page (not a dialog) to add a booking, or edit one that is not seated
/// yet. Pops with `true` when saved. Only tables that seat the party and are free
/// at the chosen time are offered, and the server checks again when saving.
class ReservationFormPage extends StatefulWidget {
  final Reservation? existing;
  const ReservationFormPage({super.key, this.existing});

  @override
  State<ReservationFormPage> createState() => _ReservationFormPageState();
}

class _ReservationFormPageState extends State<ReservationFormPage> {
  final _repo = ReservationRepository();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();

  int _guests = 2;
  late DateTime _date;
  late TimeOfDay _time;

  List<Map<String, dynamic>> _tables = [];
  int? _tableId;
  bool _loadingTables = false;
  String? _tablesError;
  Timer? _debounce;
  int _tablesRequest = 0; // so a slow, older answer can't overwrite a newer one

  bool _saving = false;
  String? _nameError;
  String? _phoneError;
  String? _formError;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.customerName;
      _phone.text = e.contactNumber ?? '';
      _notes.text = e.notes ?? '';
      _guests = e.guestCount;
      final dt = e.dateTime ?? DateTime.now();
      _date = DateTime(dt.year, dt.month, dt.day);
      _time = TimeOfDay(hour: dt.hour, minute: dt.minute);
      _tableId = e.tableId;
    } else {
      final start = _nextSlot();
      _date = DateTime(start.year, start.month, start.day);
      _time = TimeOfDay(hour: start.hour, minute: start.minute);
    }
    _loadTables();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The next half hour that is at least 30 minutes away.
  DateTime _nextSlot() {
    final t = DateTime.now().add(const Duration(minutes: 30));
    final minutes = t.minute == 0 ? 0 : (t.minute <= 30 ? 30 : 60);
    return DateTime(t.year, t.month, t.day, t.hour).add(Duration(minutes: minutes));
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_date);
  String get _timeStr => '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}:00';
  DateTime get _when => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  /// True when editing and the date and time were left as they were.
  bool get _timeUnchanged {
    final e = widget.existing;
    return e != null && e.reservationDate == _dateStr && e.reservationTime == _timeStr;
  }

  // ---- tables ----

  Future<void> _loadTables() async {
    final id = ++_tablesRequest;
    setState(() {
      _loadingTables = true;
      _tablesError = null;
    });
    try {
      final tables = await _repo.getAvailableTables(
        date: _dateStr,
        time: _timeStr,
        guestCount: _guests,
        excludeReservationId: widget.existing?.reservationId,
      );
      if (!mounted || id != _tablesRequest) return;
      setState(() {
        _tables = tables;
        // Keep the chosen table if it is still free, otherwise pick the smallest that fits.
        if (!tables.any((t) => t['table_id'] == _tableId)) {
          _tableId = tables.isNotEmpty ? tables.first['table_id'] as int : null;
        }
        _loadingTables = false;
      });
    } catch (e) {
      if (!mounted || id != _tablesRequest) return;
      setState(() {
        _tablesError = '$e';
        _loadingTables = false;
      });
    }
  }

  /// Waits a moment after the last change before asking for tables again.
  void _scheduleTables() {
    _debounce?.cancel();
    setState(() {
      _loadingTables = true;
      _formError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 300), _loadTables);
  }

  // ---- pickers ----

  void _changeGuests(int delta) {
    final next = (_guests + delta).clamp(1, _maxGuests);
    if (next == _guests) return;
    setState(() => _guests = next);
    _scheduleTables();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final first = _date.isBefore(todayDate) ? _date : todayDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: first,
      lastDate: todayDate.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _date = picked);
    _scheduleTables();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    setState(() => _time = picked);
    _scheduleTables();
  }

  // ---- save ----

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();

    String? nameError;
    String? phoneError;
    String? formError;
    if (name.length < 2) nameError = 'Enter the customer name';
    if (phone.isNotEmpty && !RegExp(r'^[0-9+\-\s()]{7,20}$').hasMatch(phone)) {
      phoneError = 'Use digits, spaces and + - ( ) only (7 to 20 characters)';
    }
    if (_tableId == null) {
      formError = 'Choose a table. Try another time or a smaller party if none is free.';
    } else if (!_timeUnchanged && _when.isBefore(DateTime.now().subtract(const Duration(minutes: 5)))) {
      formError = 'That date and time has already passed.';
    }

    setState(() {
      _nameError = nameError;
      _phoneError = phoneError;
      _formError = formError;
    });
    if (nameError != null || phoneError != null || formError != null) return;

    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await _repo.create(
          tableId: _tableId!,
          customerName: name,
          contactNumber: phone,
          date: _dateStr,
          time: _timeStr,
          guestCount: _guests,
          notes: _notes.text.trim(),
        );
      } else {
        await _repo.update(
          existing.reservationId,
          tableId: _tableId!,
          customerName: name,
          contactNumber: phone,
          date: _dateStr,
          time: _timeStr,
          guestCount: _guests,
          notes: _notes.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = '$e';
      });
      // The table may have just been taken: refresh what is free.
      _loadTables();
    }
  }

  // ---- build ----

  InputDecoration _decoration({String? hint, String? error, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      errorText: error,
      prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _Ui.muted),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _Ui.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _Ui.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _Ui.tanDeep)),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _Ui.ink)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit booking' : 'New booking')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label('Customer name'),
                TextField(
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() => _nameError = null),
                  decoration: _decoration(error: _nameError, icon: Icons.person_outline),
                ),
                const SizedBox(height: 16),
                _label('Phone number (optional)'),
                TextField(
                  controller: _phone,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() => _phoneError = null),
                  decoration: _decoration(hint: '+63 912 345 6789', error: _phoneError, icon: Icons.phone_outlined),
                ),
                const SizedBox(height: 16),
                _label('Party size'),
                _guestStepper(),
                const SizedBox(height: 16),
                _label('Date and time'),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _pickDate,
                        icon: const Icon(Icons.calendar_today_outlined, size: 18),
                        label: Text(DateFormat('EEE, MMM d, yyyy').format(_date)),
                        style: _pickerStyle(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _pickTime,
                        icon: const Icon(Icons.access_time, size: 18),
                        label: Text(_time.format(context)),
                        style: _pickerStyle(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _label('Table'),
                _tablePicker(),
                const SizedBox(height: 16),
                _label('Notes (optional)'),
                TextField(
                  controller: _notes,
                  enabled: !_saving,
                  maxLines: 2,
                  maxLength: 255,
                  decoration: _decoration(hint: 'Birthday, window seat, high chair...'),
                ),
                if (_formError != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _Ui.red.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, size: 18, color: _Ui.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_formError!, style: const TextStyle(fontSize: 13, color: _Ui.red))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _Ui.tanDeep,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_editing ? 'Save changes' : 'Add booking'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _pickerStyle() => OutlinedButton.styleFrom(
        foregroundColor: _Ui.ink,
        backgroundColor: Colors.white,
        side: const BorderSide(color: _Ui.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _guestStepper() {
    Widget button(IconData icon, VoidCallback? onTap) => Material(
          color: const Color(0xFFEFE9E0),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 20, color: onTap == null ? _Ui.muted.withOpacity(0.5) : _Ui.tanDeep)),
          ),
        );

    return Row(
      children: [
        button(Icons.remove, _saving || _guests <= 1 ? null : () => _changeGuests(-1)),
        SizedBox(
          width: 70,
          child: Column(
            children: [
              Text('$_guests', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _Ui.ink)),
              Text(_guests == 1 ? 'guest' : 'guests', style: const TextStyle(fontSize: 11, color: _Ui.muted)),
            ],
          ),
        ),
        button(Icons.add, _saving || _guests >= _maxGuests ? null : () => _changeGuests(1)),
      ],
    );
  }

  Widget _tablePicker() {
    Widget body;
    if (_tablesError != null) {
      body = Row(
        children: [
          Expanded(child: Text("Couldn't check the tables: $_tablesError", style: const TextStyle(fontSize: 13, color: _Ui.muted))),
          TextButton(onPressed: _loadTables, child: const Text('Retry')),
        ],
      );
    } else if (_loadingTables && _tables.isEmpty) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator());
    } else if (_tables.isEmpty) {
      body = const Text(
        'No table is free at this time for this many guests. Try another time or a smaller party.',
        style: TextStyle(fontSize: 13, color: _Ui.red),
      );
    } else {
      body = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in _tables)
            ChoiceChip(
              label: Text(_tableLabel(t)),
              selected: t['table_id'] == _tableId,
              selectedColor: _Ui.tan.withOpacity(0.35),
              onSelected: _saving ? null : (_) => setState(() => _tableId = t['table_id'] as int),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        const SizedBox(height: 6),
        Row(
          children: [
            if (_loadingTables && _tables.isNotEmpty)
              const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 2))),
            const Expanded(
              child: Text(
                'Only tables that seat the party and are free around this time are shown.',
                style: TextStyle(fontSize: 11.5, color: _Ui.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _tableLabel(Map<String, dynamic> t) {
    final location = '${t['location'] ?? ''}'.trim();
    final place = location.isEmpty ? '' : ' · ${location[0].toUpperCase()}${location.substring(1)}';
    return '${t['table_number']} · seats ${t['capacity']}$place';
  }
}