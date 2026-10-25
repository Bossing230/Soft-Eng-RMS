import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/models/reservations.dart';

class ReservationStatusStyle {
  final Color color;
  final String label;
  const ReservationStatusStyle(this.color, this.label);
}

/// Color and label for each booking status, shared by the card and the page.
ReservationStatusStyle reservationStatusStyle(String status) {
  switch (status) {
    case 'pending':
      return const ReservationStatusStyle(Color(0xFFB07A00), 'Pending');
    case 'confirmed':
      return const ReservationStatusStyle(Color(0xFF1E6FBF), 'Confirmed');
    case 'seated':
      return const ReservationStatusStyle(Color(0xFF2E7D32), 'Seated');
    case 'completed':
      return const ReservationStatusStyle(Color(0xFF6D6D6D), 'Completed');
    case 'cancelled':
      return const ReservationStatusStyle(Color(0xFFD32F2F), 'Cancelled');
    case 'no_show':
      return const ReservationStatusStyle(Color(0xFF8D6E63), 'No-show');
    default:
      return ReservationStatusStyle(const Color(0xFF7A7A7A), status);
  }
}

class _PrimaryAction {
  final String action;
  final String label;
  final IconData icon;
  const _PrimaryAction(this.action, this.label, this.icon);
}

/// The one step that normally comes next, shown as the main button.
_PrimaryAction? _primaryFor(String status) {
  switch (status) {
    case 'pending':
      return const _PrimaryAction('confirmed', 'Confirm', Icons.check);
    case 'confirmed':
      return const _PrimaryAction('seated', 'Seat', Icons.event_seat_outlined);
    case 'seated':
      return const _PrimaryAction('completed', 'Complete', Icons.done_all);
    default:
      return null;
  }
}

/// "in 25 min", "in 2 h 10 min", "Starting now" or "Late 12 min" for a booking
/// that is still waiting for its guests; null otherwise.
String? reservationTiming(Reservation r) {
  if (!r.isWaiting) return null;
  final m = r.minutesUntil;
  if (m == null) return null;
  if (m >= 0) {
    if (m == 0) return 'Starting now';
    if (m < 60) return 'in $m min';
    if (m < 24 * 60) return 'in ${m ~/ 60} h ${m % 60} min';
    return null;
  }
  final late = -m;
  if (late <= 10) return 'Starting now';
  if (late < 60) return 'Late $late min';
  return 'Late ${late ~/ 60} h ${late % 60} min';
}

/// One booking. [onAction] receives 'confirmed', 'seated', 'completed',
/// 'cancelled', 'no_show' or 'edit'; the page decides what to do (and asks for
/// confirmation before cancelling).
class ReservationCard extends StatelessWidget {
  final Reservation reservation;
  final ValueChanged<String> onAction;
  final bool busy;

  const ReservationCard({super.key, required this.reservation, required this.onAction, this.busy = false});

  static const _ink = Color(0xFF2B2B2B);
  static const _muted = Color(0xFF7A7A7A);
  static const _border = Color(0xFFEBE3D8);

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final style = reservationStatusStyle(r.status);
    final dim = r.isFinished;

    return Opacity(
      opacity: dim ? 0.72 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            final details = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _timeChip(r, style),
                const SizedBox(width: 14),
                Expanded(child: _info(r, style)),
              ],
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 12),
                  _actions(r, style),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: _actions(r, style)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _timeChip(Reservation r, ReservationStatusStyle style) {
    final dt = r.dateTime;
    return Container(
      width: 84,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(color: style.color.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(
            dt == null ? r.reservationTime : DateFormat('h:mm a').format(dt),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: style.color),
          ),
          const SizedBox(height: 2),
          Text(
            dt == null ? r.reservationDate : DateFormat('MMM d').format(dt),
            style: TextStyle(fontSize: 11, color: style.color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  Widget _info(Reservation r, ReservationStatusStyle style) {
    final timing = reservationTiming(r);
    final isLate = timing != null && timing.startsWith('Late');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                r.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFF0DFCF), borderRadius: BorderRadius.circular(6)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_outline, size: 13, color: Color(0xFFB98A5E)),
                  const SizedBox(width: 3),
                  Text('${r.guestCount}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB98A5E))),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          r.tableCapacity > 0 ? 'Table ${r.tableNumber} · seats ${r.tableCapacity}' : 'Table ${r.tableNumber}',
          style: const TextStyle(fontSize: 12.5, color: _muted),
        ),
        if (r.contactNumber != null) Text(r.contactNumber!, style: const TextStyle(fontSize: 12.5, color: _muted)),
        if (r.notes != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(r.notes!, style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: _muted)),
          ),
        if (timing != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isLate ? const Color(0xFFD32F2F) : const Color(0xFF7A7A7A)).withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                timing,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: isLate ? const Color(0xFFD32F2F) : _muted),
              ),
            ),
          ),
      ],
    );
  }

  Widget _actions(Reservation r, ReservationStatusStyle style) {
    final primary = _primaryFor(r.status);
    final canEditOrCancel = r.isWaiting;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: style.color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(style.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: style.color)),
        ),
        if (primary != null) ...[
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: busy ? null : () => onAction(primary.action),
            icon: busy
                ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(primary.icon, size: 16),
            label: Text(primary.label),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB98A5E),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
        if (canEditOrCancel)
          PopupMenuButton<String>(
            tooltip: 'More',
            enabled: !busy,
            icon: const Icon(Icons.more_vert, size: 20, color: _muted),
            onSelected: onAction,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text('Edit booking')])),
              PopupMenuItem(value: 'no_show', child: Row(children: [Icon(Icons.person_off_outlined, size: 18), SizedBox(width: 10), Text('Mark no-show')])),
              PopupMenuItem(
                value: 'cancelled',
                child: Row(children: [Icon(Icons.cancel_outlined, size: 18, color: Colors.red), SizedBox(width: 10), Text('Cancel booking', style: TextStyle(color: Colors.red))]),
              ),
            ],
          ),
      ],
    );
  }
}