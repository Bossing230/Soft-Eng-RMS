import 'package:rms/Frontend/models/account_profile.dart';
import 'package:rms/Frontend/services/api_services.dart';

class AccountRepository {
  final ApiService _api = ApiService();

  Future<AccountProfile> getProfile() async {
    final data = await _api.get('/account/profile');
    return AccountProfile.fromJson(Map<String, dynamic>.from(data));
  }

  /// Saves the three editable fields. Email, role and username can't be changed here.
  Future<AccountProfile> updateProfile({
    required String name,
    required String phone,
    required String address,
  }) async {
    final data = await _api.put('/account/profile', body: {
      'name': name,
      'phone': phone,
      'address': address,
    });
    return AccountProfile.fromJson(Map<String, dynamic>.from(data));
  }

  /// Uploads a new profile photo and returns its permanent URL.
  Future<String> uploadPhoto({required List<int> bytes, required String filename}) async {
    final data = await _api.uploadFile('/account/photo', bytes: bytes, filename: filename);
    return data['profile_image'] as String;
  }

  /// The tax and service-charge rates applied to every order (e.g. 0.12 = 12%).
  Future<Map<String, dynamic>> getOrderRates() async {
    final data = await _api.get('/config/order-rates');
    return Map<String, dynamic>.from(data);
  }
}