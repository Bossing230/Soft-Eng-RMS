import 'package:rms/Frontend/models/supplier.dart';
import 'package:rms/Frontend/services/api_services.dart';

class SupplierRepository {
  final ApiService _api = ApiService();

  Future<List<Supplier>> getAll() async {
    final data = await _api.get('/suppliers');
    return (data as List).map((e) => Supplier.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Map<String, dynamic> _body(String name, String contactPerson, String phone, String email, String address, String notes) => {
        'name': name,
        'contactPerson': contactPerson,
        'phone': phone,
        'email': email,
        'address': address,
        'notes': notes,
      };

  Future<Supplier> create({
    required String name,
    String contactPerson = '',
    String phone = '',
    String email = '',
    String address = '',
    String notes = '',
  }) async {
    final data = await _api.post('/suppliers', body: _body(name, contactPerson, phone, email, address, notes));
    return Supplier.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Supplier> update(
    int id, {
    required String name,
    String contactPerson = '',
    String phone = '',
    String email = '',
    String address = '',
    String notes = '',
  }) async {
    final data = await _api.put('/suppliers/$id', body: _body(name, contactPerson, phone, email, address, notes));
    return Supplier.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> remove(int id) => _api.post('/suppliers/$id/delete', body: {});
}