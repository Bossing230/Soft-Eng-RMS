class Reservation {
  final int reservationId;
  final int tableId;
  final String tableNumber;
  final int tableCapacity;
  final String customerName;
  final String? contactNumber;

  /// 'YYYY-MM-DD'
  final String reservationDate;

  /// 'HH:MM:SS'
  final String reservationTime;
  final int guestCount;

  /// pending | confirmed | seated | completed | cancelled | no_show
  final String status;
  final String? notes;

  /// Minutes from now (restaurant time) until the booking: negative once the
  /// time has passed. Worked out by the server, so the app needs no clock.
  final int? minutesUntil;

  Reservation({
    required this.reservationId,
    required this.tableId,
    required this.tableNumber,
    this.tableCapacity = 0,
    required this.customerName,
    this.contactNumber,
    required this.reservationDate,
    required this.reservationTime,
    required this.guestCount,
    required this.status,
    this.notes,
    this.minutesUntil,
  });

  factory Reservation.fromJson(Map<String, dynamic> json) {
    String? textOrNull(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return Reservation(
      reservationId: int.parse(json['reservation_id'].toString()),
      tableId: int.parse(json['table_id'].toString()),
      tableNumber: (json['table_number'] ?? '').toString(),
      tableCapacity: int.tryParse('${json['table_capacity']}') ?? 0,
      customerName: (json['customer_name'] ?? '').toString(),
      contactNumber: textOrNull(json['contact_number']),
      reservationDate: (json['reservation_date'] ?? '').toString(),
      reservationTime: (json['reservation_time'] ?? '').toString(),
      guestCount: int.parse(json['guest_count'].toString()),
      status: (json['status'] ?? 'pending').toString(),
      notes: textOrNull(json['notes']),
      minutesUntil: int.tryParse('${json['minutes_until']}'),
    );
  }

  /// The booking's date and time as one value (restaurant wall-clock time).
  DateTime? get dateTime => DateTime.tryParse('${reservationDate}T$reservationTime');

  /// Still waiting for the guests (pending or confirmed).
  bool get isWaiting => status == 'pending' || status == 'confirmed';

  /// Still using its table: waiting or seated.
  bool get isActive => isWaiting || status == 'seated';

  /// Completed, cancelled or no-show.
  bool get isFinished => !isActive;
}

/// Today's summary numbers.
class ReservationStats {
  final int bookings;
  final int guestsExpected;
  final int seated;
  final int cancelled;

  const ReservationStats({this.bookings = 0, this.guestsExpected = 0, this.seated = 0, this.cancelled = 0});

  factory ReservationStats.fromJson(Map<String, dynamic> json) {
    return ReservationStats(
      bookings: int.tryParse('${json['bookings']}') ?? 0,
      guestsExpected: int.tryParse('${json['guests_expected']}') ?? 0,
      seated: int.tryParse('${json['seated']}') ?? 0,
      cancelled: int.tryParse('${json['cancelled']}') ?? 0,
    );
  }
}

/// The numbers shown on the filter chips.
class ReservationCounts {
  final int today;
  final int upcoming;
  final int cancelled;

  const ReservationCounts({this.today = 0, this.upcoming = 0, this.cancelled = 0});

  factory ReservationCounts.fromJson(Map<String, dynamic> json) {
    return ReservationCounts(
      today: int.tryParse('${json['today']}') ?? 0,
      upcoming: int.tryParse('${json['upcoming']}') ?? 0,
      cancelled: int.tryParse('${json['cancelled']}') ?? 0,
    );
  }
}

/// Everything the Reservations page shows, from one request.
class ReservationBoard {
  final List<Reservation> reservations;
  final ReservationStats stats;
  final ReservationCounts counts;

  /// The restaurant's today, 'YYYY-MM-DD'.
  final String today;

  ReservationBoard({required this.reservations, required this.stats, required this.counts, required this.today});

  factory ReservationBoard.fromJson(Map<String, dynamic> json) {
    return ReservationBoard(
      reservations: ((json['reservations'] as List?) ?? [])
          .map((e) => Reservation.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      stats: ReservationStats.fromJson(Map<String, dynamic>.from((json['stats'] as Map?) ?? const {})),
      counts: ReservationCounts.fromJson(Map<String, dynamic>.from((json['counts'] as Map?) ?? const {})),
      today: (json['today'] ?? '').toString(),
    );
  }
}