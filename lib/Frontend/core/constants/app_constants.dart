/// Central place for environment-dependent constants.
/// Override API_BASE_URL at build time with:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:4000/api
class AppConstants {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://soft-eng-rms-backend.onrender.com/api',
  );

  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'https://soft-eng-rms-backend.onrender.com',
  );

  static const String appName = 'D Hermanos Pizza';

  // Role identifiers — must match backend `roles.role_name` values.
  static const String roleAdmin = 'administrator';
  static const String roleManager = 'manager';
  static const String roleCashier = 'cashier';
  static const String roleKitchen = 'kitchen';
}