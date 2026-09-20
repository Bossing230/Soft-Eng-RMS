import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/models/reservations.dart';
import 'package:rms/Frontend/repositories/reservation_repository.dart';
import '../../models/dining_table.dart';
import '../../widgets/reservation_card.dart';

class ReservationPage extends StatefulWidget {
  const ReservationPage({super.key});

  @override
  State<ReservationPage> createState() => _ReservationPageState();
}

class _ReservationPageState extends State<ReservationPage> {
  final _repo = ReservationRepository();
  List<Reservation> _reservations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _repo.getAll();
    setState(() {
      _reservations = data;
      _loading = false;
    });
  }

  Future<void> _showCreateDialog() async {
    final nameCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final guestsCtrl = TextEditingController(text: '2');
    DateTime date = DateTime.now();
    TimeOfDay time = TimeOfDay.now();
    List<DiningTable> availableTables = [];
    int? selectedTableId;

    Future<void> refreshTables(StateSetter setDialogState) async {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
      final tables = await _repo.getAvailableTables(date: dateStr, time: timeStr, guestCount: int.tryParse(guestsCtrl.text) ?? 1);
      setDialogState(() {
        availableTables = tables;
        selectedTableId = tables.isNotEmpty ? tables.first.tableId : null;
      });
    }

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (availableTables.isEmpty) refreshTables(setDialogState);
          return AlertDialog(
            title: const Text('New Reservation'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Customer name')),
                TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contact number')),
                TextField(controller: guestsCtrl, decoration: const InputDecoration(labelText: 'Guests'), keyboardType: TextInputType.number, onChanged: (_) => refreshTables(setDialogState)),
                ListTile(
                  title: Text('Date: ${DateFormat('yyyy-MM-dd').format(date)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
                    if (picked != null) { date = picked; await refreshTables(setDialogState); }
                  },
                ),
                ListTile(
                  title: Text('Time: ${time.format(ctx)}'),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final picked = await showTimePicker(context: ctx, initialTime: time);
                    if (picked != null) { time = picked; await refreshTables(setDialogState); }
                  },
                ),
                if (availableTables.isEmpty)
                  const Padding(padding: EdgeInsets.all(8), child: Text('No tables available for this date/time/party size.', style: TextStyle(color: Colors.red)))
                else
                  DropdownButtonFormField<int>(
                    value: selectedTableId,
                    items: availableTables.map((t) => DropdownMenuItem(value: t.tableId, child: Text('${t.tableNumber} (seats ${t.capacity})'))).toList(),
                    onChanged: (v) => setDialogState(() => selectedTableId = v),
                    decoration: const InputDecoration(labelText: 'Table'),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: selectedTableId == null ? null : () => Navigator.pop(ctx, true), child: const Text('Reserve')),
            ],
          );
        },
      ),
    );

    if (created == true && selectedTableId != null) {
      try {
        await _repo.create(
          tableId: selectedTableId!,
          customerName: nameCtrl.text,
          contactNumber: contactCtrl.text,
          date: DateFormat('yyyy-MM-dd').format(date),
          time: '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00',
          guestCount: int.tryParse(guestsCtrl.text) ?? 1,
        );
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _showCreateDialog, icon: const Icon(Icons.add), label: const Text('New Reservation')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _reservations.length,
                itemBuilder: (_, i) {
                  final r = _reservations[i];
                  return ReservationCard(
                    reservation: r,
                    actions: r.status == 'pending' || r.status == 'confirmed'
                        ? [
                            IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), tooltip: 'Seat', onPressed: () async { await _repo.setStatus(r.reservationId, 'seated'); _load(); }),
                            IconButton(icon: const Icon(Icons.cancel, color: Colors.red), tooltip: 'Cancel', onPressed: () async { await _repo.setStatus(r.reservationId, 'cancelled'); _load(); }),
                          ]
                        : [],
                  );
                },
              ),
            ),
    );
  }
}