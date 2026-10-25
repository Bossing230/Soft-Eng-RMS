import 'package:rms/Frontend/models/reservations.dart';
import 'package:rms/Frontend/services/api_services.dart';

class ReservationRepository {
  final ApiService _api = ApiService();

  /// Everything the Reservations page shows. [scope] is 'today', 'upcoming',
  /// 'all', 'cancelled' or 'date' (then pass [date] as 'YYYY-MM-DD').
  Future<ReservationBoard> getBoard({String scope = 'today', String? date, String? search}) async {
    final data = await _api.get('/reservations/board', query: {
      'scope': scope,
      if (date != null) 'date': date,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    });
    return ReservationBoard.fromJson(Map<String, dynamic>.from(data));
  }

  /// Tables that fit [guestCount] and are free around [time] ('HH:MM:00').
  /// Pass [excludeReservationId] when editing, so a booking doesn't block itself.
  /// Each map has table_id, table_number, capacity, location and status.
  Future<List<Map<String, dynamic>>> getAvailableTables({
    required String date,
    required String time,
    required int guestCount,
    int? excludeReservationId,
  }) async {
    final data = await _api.get('/reservations/available-tables', query: {
      'date': date,
      'time': time,
      'guestCount': guestCount,
      if (excludeReservationId != null) 'excludeId': excludeReservationId,
    });
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Reservation> create({
    required int tableId,
    required String customerName,
    String? contactNumber,
    required String date,
    required String time,
    required int guestCount,
    String? notes,
  }) async {
    final data = await _api.post('/reservations', body: {
      'tableId': tableId,
      'customerName': customerName,
      'contactNumber': contactNumber ?? '',
      'date': date,
      'time': time,
      'guestCount': guestCount,
      'notes': notes ?? '',
    });
    return Reservation.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Reservation> update(
    int reservationId, {
    required int tableId,
    required String customerName,
    String? contactNumber,
    required String date,
    required String time,
    required int guestCount,
    String? notes,
  }) async {
    final data = await _api.put('/reservations/$reservationId', body: {
      'tableId': tableId,
      'customerName': customerName,
      'contactNumber': contactNumber ?? '',
      'date': date,
      'time': time,
      'guestCount': guestCount,
      'notes': notes ?? '',
    });
    return Reservation.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Reservation> setStatus(int reservationId, String status) async {
    final data = await _api.patch('/reservations/$reservationId/status', body: {'status': status});
    return Reservation.fromJson(Map<String, dynamic>.from(data));
  }
}