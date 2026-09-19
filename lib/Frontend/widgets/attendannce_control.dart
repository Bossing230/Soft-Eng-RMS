import 'package:flutter/material.dart';
import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import '../repositories/attendance_repository.dart';

/// Clock in / break / clock out control for the top bar.
///
/// Only cashier and kitchen staff are tracked, so this renders nothing for
/// any other role (and nothing until the server has answered, so an older
/// backend without the attendance routes simply hides it).
class AttendanceControl extends StatefulWidget {
  /// Icon-only version for narrow app bars.
  final bool compact;
  const AttendanceControl({super.key, this.compact = false});

  @override
  State<AttendanceControl> createState() => _AttendanceControlState();
}

class _AttendanceControlState extends State<AttendanceControl> {
  static const _trackedRoles = {'cashier', 'kitchen'};

  final _repo = AttendanceRepository();
  String _status = 'off'; // 'off' | 'on_duty' | 'on_break'
  bool _loaded = false;
  bool _busy = false;

  bool get _enabled => _trackedRoles.contains((SessionManager().role ?? '').toLowerCase());

  @override
  void initState() {
    super.initState();
    if (_enabled) _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await _repo.getStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _loaded = true;
        });
      }
    } catch (_) {
      // Stay hidden if the status can't be read.
    }
  }

  Future<void> _run(Future<String> Function() action, String doneMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await action();
      if (!mounted) return;
      setState(() => _status = next);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(doneMessage)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      _loadStatus(); // resync in case the status changed somewhere else
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled || !_loaded) return const SizedBox.shrink();

    if (_status == 'off') {
      final onPressed = _busy ? null : () => _run(_repo.clockIn, 'Clocked in');
      return widget.compact
          ? IconButton(tooltip: 'Clock in', onPressed: onPressed, icon: const Icon(Icons.login))
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Clock in'),
            );
    }

    final onBreak = _status == 'on_break';
    final color = onBreak ? Colors.amber[700]! : Colors.green;
    final label = onBreak ? 'On break' : 'On duty';

    return PopupMenuButton<String>(
      tooltip: 'Attendance',
      enabled: !_busy,
      onSelected: (value) {
        switch (value) {
          case 'break_start':
            _run(_repo.startBreak, 'Break started');
            break;
          case 'break_end':
            _run(_repo.endBreak, 'Back on duty');
            break;
          case 'clock_out':
            _run(_repo.clockOut, 'Clocked out');
            break;
        }
      },
      itemBuilder: (_) => [
        if (!onBreak) const PopupMenuItem(value: 'break_start', child: Text('Start break')),
        if (onBreak) const PopupMenuItem(value: 'break_end', child: Text('End break')),
        const PopupMenuItem(value: 'clock_out', child: Text('Clock out')),
      ],
      child: widget.compact
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Badge(smallSize: 9, backgroundColor: color, child: const Icon(Icons.access_time)),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 9, color: color),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                  const Icon(Icons.arrow_drop_down, size: 18, color: Colors.black54),
                ],
              ),
            ),
    );
  }
}