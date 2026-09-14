class Employee {
  final int employeeId;
  final String name;
  final String username;
  final String email;
  final String role;
  final String status;
  final String? profileImage;

  Employee({
    required this.employeeId,
    required this.name,
    required this.username,
    required this.email,
    required this.role,
    required this.status,
    this.profileImage,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      employeeId: json['employee_id'] is int ? json['employee_id'] : int.parse(json['employee_id'].toString()),
      name: json['name'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      role: json['role_name'] ?? json['role'] ?? '',
      status: json['status'] ?? 'active',
      profileImage: json['profile_image'],
    );
  }
}