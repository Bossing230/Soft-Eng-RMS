import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/reservations.dart';

class ReservationCard extends StatelessWidget {
  final Reservation reservation;
  final List<Widget> actions;

  const ReservationCard({super.key, required this.reservation, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('${reservation.customerName} — Table ${reservation.tableNumber}'),
        subtitle: Text('${reservation.reservationDate} at ${reservation.reservationTime} • ${reservation.guestCount} guests'),
        trailing: actions.isNotEmpty
            ? Row(mainAxisSize: MainAxisSize.min, children: actions)
            : Chip(label: Text(reservation.status), visualDensity: VisualDensity.compact),
      ),
    );
  }
}