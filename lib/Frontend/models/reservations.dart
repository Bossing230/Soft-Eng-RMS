class Reservation {
  final int reservationId;
  final int tableId;
  final String tableNumber;
  final String customerName;
  final String? contactNumber;
  final String reservationDate;
  final String reservationTime;
  final int guestCount;
  final String status;

  Reservation({
    required this.reservationId,
    required this.tableId,
    required this.tableNumber,
    required this.customerName,
    this.contactNumber,
    required this.reservationDate,
    required this.reservationTime,
    required this.guestCount,
    required this.status,
  });

  factory Reservation.fromJson(Map<String, dynamic> json) {
    return Reservation(
      reservationId: int.parse(json['reservation_id'].toString()),
      tableId: int.parse(json['table_id'].toString()),
      tableNumber: json['table_number'] ?? '',
      customerName: json['customer_name'] ?? '',
      contactNumber: json['contact_number'],
      reservationDate: json['reservation_date'] ?? '',
      reservationTime: json['reservation_time'] ?? '',
      guestCount: int.parse(json['guest_count'].toString()),
      status: json['status'] ?? 'pending',
    );
  }
}