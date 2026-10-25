/// The signed-in person's own profile, as shown on the Account Settings page.
class AccountProfile {
  final int employeeId;
  final String name;
  final String username;
  final String email;
  final String role;
  final String phone;
  final String address;
  final String? profileImage;

  /// Restaurant-local 'YYYY-MM-DD HH:MM:SS', or null if no login was recorded yet.
  final String? lastLogin;

  AccountProfile({
    required this.employeeId,
    required this.name,
    required this.username,
    required this.email,
    required this.role,
    required this.phone,
    required this.address,
    this.profileImage,
    this.lastLogin,
  });

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    String? textOrNull(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return AccountProfile(
      employeeId: int.tryParse('${json['employee_id']}') ?? 0,
      name: (json['name'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      profileImage: textOrNull(json['profile_image']),
      lastLogin: textOrNull(json['last_login']),
    );
  }

  AccountProfile copyWith({String? profileImage}) {
    return AccountProfile(
      employeeId: employeeId,
      name: name,
      username: username,
      email: email,
      role: role,
      phone: phone,
      address: address,
      profileImage: profileImage ?? this.profileImage,
      lastLogin: lastLogin,
    );
  }
}