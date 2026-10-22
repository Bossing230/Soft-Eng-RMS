/// One line of the Activity Log.
class ActivityLogEntry {
  final int id;

  /// What kind of badge to show: 'login', 'logout', 'password', or a module
  /// name such as 'orders', 'menu', 'inventory'.
  final String kind;
  final String module;

  /// The description of what happened, e.g. "Created order #12".
  final String details;

  /// Restaurant-local, 'YYYY-MM-DD HH:MM:SS'.
  final String time;
  final int userId;
  final String userName;
  final String role;

  /// Null for entries written before IP and device were recorded.
  final String? ip;
  final String? device;

  ActivityLogEntry({
    required this.id,
    required this.kind,
    required this.module,
    required this.details,
    required this.time,
    required this.userId,
    required this.userName,
    required this.role,
    this.ip,
    this.device,
  });

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json) {
    String? textOrNull(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return ActivityLogEntry(
      id: int.tryParse('${json['id']}') ?? 0,
      kind: (json['kind'] ?? json['module'] ?? '').toString(),
      module: (json['module'] ?? '').toString(),
      details: (json['details'] ?? '').toString(),
      time: (json['time'] ?? '').toString(),
      userId: int.tryParse('${json['user_id']}') ?? 0,
      userName: (json['user_name'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      ip: textOrNull(json['ip']),
      device: textOrNull(json['device']),
    );
  }
}

/// One page of results plus how many entries match the filters in total.
class ActivityLogPageResult {
  final List<ActivityLogEntry> logs;
  final int total;
  final int page;
  final int limit;

  ActivityLogPageResult({required this.logs, required this.total, required this.page, required this.limit});

  factory ActivityLogPageResult.fromJson(Map<String, dynamic> json) {
    return ActivityLogPageResult(
      logs: ((json['logs'] as List?) ?? [])
          .map((e) => ActivityLogEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      total: int.tryParse('${json['total']}') ?? 0,
      page: int.tryParse('${json['page']}') ?? 1,
      limit: int.tryParse('${json['limit']}') ?? 10,
    );
  }
}