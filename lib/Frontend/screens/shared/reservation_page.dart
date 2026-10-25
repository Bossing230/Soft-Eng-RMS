import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/models/reservations.dart';
import 'package:rms/Frontend/repositories/reservation_repository.dart';
import 'package:rms/Frontend/widgets/reservation_form_page.dart';
import '../../widgets/reservation_card.dart';
// ---------------------------------------------------------------------------
// Design tokens, shared with the other management pages.
// ---------------------------------------------------------------------------
class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const tan = Color(0xFFD4A574);
  static const tanDeep = Color(0xFFB98A5E);
  static const searchFill = Color(0xFFF1EBE4);
  static const pillIdle = Color(0xFFEFE9E0);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
}

/// Reservations: today's summary, filters (Today / Upcoming / All / Cancelled /
/// a chosen date), search, and the bookings grouped by time or day. It refreshes
/// itself every 30 seconds so "in 25 min" and "Late 12 min" stay current.
class ReservationPage extends StatefulWidget {
  const ReservationPage({super.key});

  @override
  State<ReservationPage> createState() => _ReservationPageState();
}

class _ReservationPageState extends State<ReservationPage> {
  final _repo = ReservationRepository();
  final _searchController = TextEditingController();
  Timer? _timer;
  Timer? _debounce;
  int _requestId = 0; // so a slow, older answer can't overwrite a newer one

  String _scope = 'today'; // today | upcoming | all | cancelled | date
  DateTime? _pickedDate;
  String _search = '';

  ReservationBoard? _board;
  bool _loading = true; // only until the very first answer
  bool _refreshing = false; // thin progress line while reloading
  String? _error;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Fetches fresh data. A failed background refresh keeps the last good list on
  /// screen; a failed pull-to-refresh tells the user.
  Future<void> _load({bool manual = false}) async {
    final id = ++_requestId;
    if (_board != null && mounted) setState(() => _refreshing = true);
    try {
      final board = await _repo.getBoard(
        scope: _scope,
        date: _scope == 'date' && _pickedDate != null ? DateFormat('yyyy-MM-dd').format(_pickedDate!) : null,
        search: _search,
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _board = board;
        _error = null;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _refreshing = false;
        if (_board == null) {
          _error = '$e';
          _loading = false;
        }
      });
      if (_board != null && manual) _snack('Could not refresh: $e');
    }
  }

  void _setScope(String scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    _load();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickedDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      _pickedDate = picked;
      _scope = 'date';
    });
    _load();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _search = value.trim());
      _load();
    });
  }

  // ---- actions ----

  Future<void> _openForm({Reservation? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReservationFormPage(existing: existing)),
    );
    if (saved == true) {
      _snack(existing == null ? 'Booking added' : 'Booking updated');
      _load();
    }
  }

  Future<bool> _confirm(String title, String message, String yes) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep booking')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _act(Reservation r, String action) async {
    if (action == 'edit') {
      await _openForm(existing: r);
      return;
    }
    if (action == 'cancelled') {
      if (!await _confirm('Cancel this booking?', "${r.customerName}'s booking for table ${r.tableNumber} will be cancelled.", 'Cancel booking')) return;
    } else if (action == 'no_show') {
      if (!await _confirm('Mark as no-show?', "${r.customerName} did not arrive for table ${r.tableNumber}.", 'Mark no-show')) return;
    }

    setState(() => _busyId = r.reservationId);
    try {
      await _repo.setStatus(r.reservationId, action);
      await _load();
      _snack(_doneMessage(r, action));
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  String _doneMessage(Reservation r, String action) {
    switch (action) {
      case 'confirmed':
        return "${r.customerName}'s booking confirmed";
      case 'seated':
        return '${r.customerName} seated at table ${r.tableNumber}';
      case 'completed':
        return "${r.customerName}'s booking completed";
      case 'cancelled':
        return "${r.customerName}'s booking cancelled";
      default:
        return '${r.customerName} marked as no-show';
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_board == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40, color: _Ui.muted),
              const SizedBox(height: 12),
              const Text("Couldn't load the reservations", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(_error ?? 'Something went wrong.', textAlign: TextAlign.center, style: const TextStyle(color: _Ui.muted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final board = _board!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _summary(board.stats),
                  const SizedBox(height: 14),
                  _filters(board.counts),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            SizedBox(height: 3, child: _refreshing ? const LinearProgressIndicator(color: _Ui.tanDeep, backgroundColor: Colors.transparent) : null),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(manual: true),
                child: _list(board),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- summary strip ----

  Widget _summary(ReservationStats stats) {
    final tiles = <Widget>[
      _statTile(Icons.event_note_outlined, const Color(0xFF1E6FBF), '${stats.bookings}', 'Bookings today'),
      _statTile(Icons.hourglass_bottom, _Ui.tanDeep, '${stats.guestsExpected}', 'Guests still to arrive'),
      _statTile(Icons.event_seat_outlined, const Color(0xFF2E7D32), '${stats.seated}', 'Seated now'),
      _statTile(Icons.event_busy_outlined, const Color(0xFFD32F2F), '${stats.cancelled}', 'Cancelled / no-show'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth >= 700 ? 4 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: tiles.map((t) => SizedBox(width: width, child: t)).toList());
      },
    );
  }

  Widget _statTile(IconData icon, Color color, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _Ui.border)),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: _Ui.ink)),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: _Ui.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- filters ----

  Widget _chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    return Material(
      color: selected ? _Ui.tan : _Ui.pillIdle,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: selected ? Colors.white : _Ui.muted), const SizedBox(width: 6)],
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? Colors.white : _Ui.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters(ReservationCounts counts) {
    final dateLabel = _scope == 'date' && _pickedDate != null ? DateFormat('MMM d').format(_pickedDate!) : 'Pick a date';

    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip('Today (${counts.today})', _scope == 'today', () => _setScope('today')),
        _chip('Upcoming (${counts.upcoming})', _scope == 'upcoming', () => _setScope('upcoming')),
        _chip('All', _scope == 'all', () => _setScope('all')),
        _chip('Cancelled (${counts.cancelled})', _scope == 'cancelled', () => _setScope('cancelled')),
        _chip(dateLabel, _scope == 'date', _pickDate, icon: Icons.calendar_today_outlined),
      ],
    );

    final newBooking = ElevatedButton.icon(
      onPressed: () => _openForm(),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('New booking'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _Ui.tan,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );

    final search = TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Search name, phone or table...',
        prefixIcon: const Icon(Icons.search, size: 20, color: _Ui.muted),
        filled: true,
        fillColor: _Ui.searchFill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.tan)),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: chips), const SizedBox(width: 12), newBooking]),
              const SizedBox(height: 10),
              search,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [chips, const SizedBox(height: 10), search, const SizedBox(height: 10), newBooking],
        );
      },
    );
  }

  // ---- list ----

  Widget _list(ReservationBoard board) {
    final items = <Widget>[];

    Widget card(Reservation r) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ReservationCard(reservation: r, busy: _busyId == r.reservationId, onAction: (a) => _act(r, a)),
        );

    if (_scope == 'today') {
      final active = board.reservations.where((r) => r.isActive).toList();
      final finished = board.reservations.where((r) => r.isFinished).toList();
      if (active.isNotEmpty) {
        items.add(_header('Now & next', active.length));
        items.addAll(active.map(card));
      }
      if (finished.isNotEmpty) {
        items.add(_header('Finished', finished.length));
        items.addAll(finished.map(card));
      }
    } else {
      // Group by day, keeping the order the server sent.
      String? currentDate;
      var group = <Reservation>[];
      void flush() {
        if (currentDate == null || group.isEmpty) return;
        items.add(_header(_dayLabel(currentDate, board.today), group.length));
        items.addAll(group.map(card));
        group = <Reservation>[];
      }

      for (final r in board.reservations) {
        if (r.reservationDate != currentDate) {
          flush();
          currentDate = r.reservationDate;
        }
        group.add(r);
      }
      flush();
    }

    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                const Icon(Icons.event_available_outlined, size: 40, color: _Ui.muted),
                const SizedBox(height: 10),
                Text(_emptyText(), textAlign: TextAlign.center, style: const TextStyle(color: _Ui.muted)),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: items,
    );
  }

  String _emptyText() {
    if (_search.isNotEmpty) return 'No bookings match "$_search".';
    switch (_scope) {
      case 'today':
        return 'No bookings for today yet.\nTap "New booking" to add one.';
      case 'upcoming':
        return 'No upcoming bookings.';
      case 'cancelled':
        return 'No cancelled bookings.';
      case 'date':
        return 'No bookings on this day.';
      default:
        return 'No bookings yet.';
    }
  }

  Widget _header(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _Ui.ink)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _Ui.pillIdle, borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _Ui.muted)),
          ),
        ],
      ),
    );
  }

  /// "Sat, Oct 24 · Today", "Sun, Oct 25 · Tomorrow", or just the date.
  String _dayLabel(String date, String today) {
    final day = DateTime.tryParse(date);
    final base = DateTime.tryParse(today);
    if (day == null) return date;
    final text = DateFormat('EEE, MMM d').format(day);
    if (base == null) return text;
    final diff = DateTime(day.year, day.month, day.day).difference(DateTime(base.year, base.month, base.day)).inDays;
    if (diff == 0) return '$text · Today';
    if (diff == 1) return '$text · Tomorrow';
    if (diff == -1) return '$text · Yesterday';
    return text;
  }
}