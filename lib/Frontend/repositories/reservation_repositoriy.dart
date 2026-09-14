
import 'package:rms/Frontend/models/reservations.dart';
import 'package:rms/Frontend/services/api_services.dart';

import '../models/dining_table.dart';

class ReservationRepository {
  final ApiService _api = ApiService();

  Future<List<Reservation>> getAll({String? date, String? status}) async {
    final data = await _api.get('/reservations', query: {
      if (date != null) 'date': date,
      if (status != null) 'status': status,
    });
    return (data as List).map((e) => Reservation.fromJson(e)).toList();
  }

  Future<List<DiningTable>> getAvailableTables({required String date, required String time, required int guestCount}) async {
    final data = await _api.get('/reservations/available-tables', query: {
      'date': date, 'time': time, 'guestCount': guestCount,
    });
    return (data as List).map((e) => DiningTable.fromJson(e)).toList();
  }

  Future<Reservation> create({
    required int tableId,
    required String customerName,
    String? contactNumber,
    required String date,
    required String time,
    required int guestCount,
  }) async {
    final data = await _api.post('/reservations', body: {
      'tableId': tableId,
      'customerName': customerName,
      'contactNumber': contactNumber,
      'date': date,
      'time': time,
      'guestCount': guestCount,
    });
    return Reservation.fromJson(data);
  }

  Future<Reservation> setStatus(int reservationId, String status) async {
    final data = await _api.patch('/reservations/$reservationId/status', body: {'status': status});
    return Reservation.fromJson(data);
  }
}