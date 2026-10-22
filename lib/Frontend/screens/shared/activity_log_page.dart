import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/core/constants/app_constants.dart';
import 'package:rms/Frontend/models/activity_log.dart';
import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import 'package:rms/Frontend/repositories/activity_log_repository.dart';
// ---------------------------------------------------------------------------
// Design tokens, shared with the Inventory page so the two match.
// ---------------------------------------------------------------------------
class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const tan = Color(0xFFD4A574);
  static const tanDeep = Color(0xFFB98A5E);
  static const searchFill = Color(0xFFF1EBE4);
  static const fieldFill = Color(0xFFFBF5F0);
  static const headerFill = Color(0xFFFAF6F1);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
}

class _KindStyle {
  final String label;
  final IconData icon;
  final Color color;
  const _KindStyle(this.label, this.icon, this.color);
}

/// Icon, color and label for each kind of activity. Any module that is not
/// listed here still shows up, with its name and a neutral icon.
_KindStyle _kindStyle(String kind) {
  switch (kind) {
    case 'login':
      return const _KindStyle('Login', Icons.login, Color(0xFF2E7D32));
    case 'logout':
      return const _KindStyle('Logout', Icons.logout, Color(0xFFE53935));
    case 'password':
      return const _KindStyle('Password', Icons.lock_outline, Color(0xFF3F6FD8));
    case 'orders':
      return const _KindStyle('Orders', Icons.receipt_long_outlined, Color(0xFF3F6FD8));
    case 'menu':
      return const _KindStyle('Menu', Icons.restaurant_menu, Color(0xFFEF8A1F));
    case 'inventory':
      return const _KindStyle('Inventory', Icons.inventory_2_outlined, Color(0xFF7E57C2));
    case 'reservations':
      return const _KindStyle('Reservations', Icons.event_outlined, Color(0xFF00897B));
    case 'payments':
      return const _KindStyle('Payments', Icons.payments_outlined, Color(0xFF2E7D32));
    case 'employees':
      return const _KindStyle('Employees', Icons.badge_outlined, Color(0xFF5C6BC0));
    case 'tables':
      return const _KindStyle('Tables', Icons.table_bar_outlined, Color(0xFF8D6E63));
    case 'attendance':
      return const _KindStyle('Attendance', Icons.schedule, Color(0xFFB07A00));
    case 'reports':
      return const _KindStyle('Reports', Icons.bar_chart, Color(0xFF3F6FD8));
    default:
      final label = kind.isEmpty ? 'Other' : kind[0].toUpperCase() + kind.substring(1);
      return _KindStyle(label, Icons.history, const Color(0xFF7A7A7A));
  }
}

IconData _deviceIcon(String? device) {
  switch (device) {
    case 'Windows':
      return Icons.desktop_windows_outlined;
    case 'macOS':
      return Icons.laptop_mac;
    case 'Linux':
    case 'ChromeOS':
      return Icons.computer;
    case 'Android':
      return Icons.phone_android;
    case 'iOS':
      return Icons.phone_iphone;
    case 'App':
      return Icons.apps;
    default:
      return Icons.devices_other;
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

DateTime? _parseTime(String raw) => DateTime.tryParse(raw.replaceFirst(' ', 'T'));

/// Everything the Activity Log page needs. Opened from the profile menu, it
/// fills the main area of the role's dashboard (so it has no Scaffold of its own).
class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  static const _limit = 10;
  static const _roles = ['administrator', 'manager', 'cashier', 'kitchen'];

  final _repo = ActivityLogRepository();
  final _searchController = TextEditingController();
  Timer? _debounce;
  int _requestId = 0; // so a slow, older response can't overwrite a newer one

  late DateTimeRange _range;
  String _type = 'all';
  String _role = 'all';
  String _search = '';
  int _page = 1;

  List<String> _kinds = [];
  List<ActivityLogEntry> _logs = [];
  int _total = 0;
  bool _loading = true;
  String? _error;

  /// Administrators and managers see everyone's activity; everyone else only
  /// their own (the server enforces this too).
  bool get _seesAll {
    final role = SessionManager().role;
    return role == AppConstants.roleAdmin || role == AppConstants.roleManager;
  }

  int get _pageCount => (_total / _limit).ceil().clamp(1, 999999);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _range = DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
    _loadKinds();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadKinds() async {
    try {
      final kinds = await _repo.getKinds();
      if (mounted) setState(() => _kinds = kinds);
    } catch (_) {
      // The dropdown just stays at "All Activities".
    }
  }

  Future<void> _load() async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repo.getLogs(
        from: _range.start,
        to: _range.end,
        type: _type == 'all' ? null : _type,
        role: _seesAll && _role != 'all' ? _role : null,
        search: _search,
        page: _page,
        limit: _limit,
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _logs = result.logs;
        _total = result.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _refresh() async {
    _loadKinds();
    await _load();
  }

  void _applyFilters(VoidCallback change) {
    setState(() {
      change();
      _page = 1;
    });
    _load();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked == null) return;
    _applyFilters(() => _range = picked);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _applyFilters(() => _search = value.trim());
    });
  }

  void _goToPage(int page) {
    if (page < 1 || page > _pageCount || page == _page) return;
    setState(() => _page = page);
    _load();
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(wide ? 24 : 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    const SizedBox(height: 16),
                    _filters(),
                    const SizedBox(height: 16),
                    _tableCard(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header() {
    final df = DateFormat('MMM d, yyyy');
    final title = Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: _Ui.tanDeep, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.history, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Activity Log', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _Ui.ink)),
              Text(
                _seesAll ? 'View recent activity across all accounts.' : 'View your recent account and system activities.',
                style: const TextStyle(fontSize: 12, color: _Ui.muted),
              ),
            ],
          ),
        ),
      ],
    );

    final dateButton = OutlinedButton.icon(
      onPressed: _pickRange,
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Text('${df.format(_range.start)} - ${df.format(_range.end)}'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _Ui.ink,
        side: const BorderSide(color: _Ui.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 640) {
          return Row(children: [Expanded(child: title), dateButton]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 14), dateButton]);
      },
    );
  }

  InputDecoration _fieldDecoration({String? hint, IconData? icon, Color fill = _Ui.fieldFill}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _Ui.muted),
      filled: true,
      fillColor: fill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _Ui.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _Ui.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _Ui.tan)),
    );
  }

  Widget _filters() {
    final typeDropdown = DropdownButtonFormField<String>(
      initialValue: _type,
      isExpanded: true,
      decoration: _fieldDecoration(icon: Icons.format_list_bulleted),
      items: [
        const DropdownMenuItem(value: 'all', child: Text('All Activities')),
        for (final k in _kinds) DropdownMenuItem(value: k, child: Text(_kindStyle(k).label)),
      ],
      onChanged: (v) => _applyFilters(() => _type = v ?? 'all'),
    );

    final roleDropdown = DropdownButtonFormField<String>(
      initialValue: _role,
      isExpanded: true,
      decoration: _fieldDecoration(icon: Icons.person_outline),
      items: [
        const DropdownMenuItem(value: 'all', child: Text('All Roles')),
        for (final r in _roles) DropdownMenuItem(value: r, child: Text(_capitalize(r))),
      ],
      onChanged: (v) => _applyFilters(() => _role = v ?? 'all'),
    );

    final search = TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      decoration: _fieldDecoration(hint: 'Search activity...', icon: Icons.search, fill: _Ui.searchFill),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _Ui.border)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fields = <Widget>[typeDropdown, if (_seesAll) roleDropdown, search];
          const gap = 12.0;
          final columns = constraints.maxWidth >= 720 ? fields.length : 1;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: fields.map((f) => SizedBox(width: width, child: f)).toList(),
          );
        },
      ),
    );
  }

  Widget _tableCard() {
    Widget body;
    if (_error != null) {
      body = _message(
        icon: Icons.cloud_off_outlined,
        text: "Couldn't load the activity log: $_error",
        action: TextButton(onPressed: _load, child: const Text('Try again')),
      );
    } else if (_loading && _logs.isEmpty) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()));
    } else if (_logs.isEmpty) {
      body = _message(icon: Icons.history, text: 'No activity found for these filters.');
    } else {
      body = LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 860;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) _tableHeader(),
              for (var i = 0; i < _logs.length; i++) ...[
                if (i > 0 || wide) const Divider(height: 1, color: _Ui.border),
                wide ? _wideRow(_logs[i]) : _compactRow(_logs[i]),
              ],
            ],
          );
        },
      );
    }

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _Ui.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 3, child: _loading ? const LinearProgressIndicator(color: _Ui.tanDeep, backgroundColor: Colors.transparent) : null),
          body,
          if (_error == null && _total > 0) ...[
            const Divider(height: 1, color: _Ui.border),
            _pagination(),
          ],
        ],
      ),
    );
  }

  Widget _message({required IconData icon, required String text, Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: _Ui.muted),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: _Ui.muted)),
            if (action != null) ...[const SizedBox(height: 8), action],
          ],
        ),
      ),
    );
  }

  // ---- wide table ----

  Widget _tableHeader() {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _Ui.muted);
    return Container(
      color: _Ui.headerFill,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SizedBox(width: 48),
          const Expanded(flex: 3, child: Text('DATE & TIME', style: style)),
          if (_seesAll) const Expanded(flex: 3, child: Text('USER', style: style)),
          const Expanded(flex: 2, child: Text('ACTION', style: style)),
          const Expanded(flex: 5, child: Text('DETAILS', style: style)),
          const Expanded(flex: 2, child: Text('IP ADDRESS', style: style)),
          const Expanded(flex: 2, child: Text('DEVICE', style: style)),
        ],
      ),
    );
  }

  Widget _wideRow(ActivityLogEntry e) {
    final style = _kindStyle(e.kind);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _iconBubble(style),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: _dateCell(e)),
          if (_seesAll) Expanded(flex: 3, child: _userCell(e)),
          Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: _badge(style))),
          Expanded(flex: 5, child: Padding(padding: const EdgeInsets.only(right: 12), child: Text(e.details, style: const TextStyle(fontSize: 12.5, color: _Ui.ink)))),
          Expanded(flex: 2, child: Text(e.ip ?? '—', style: const TextStyle(fontSize: 12, color: _Ui.ink))),
          Expanded(flex: 2, child: _deviceCell(e)),
        ],
      ),
    );
  }

  // ---- narrow list ----

  Widget _compactRow(ActivityLogEntry e) {
    final style = _kindStyle(e.kind);
    final time = _parseTime(e.time);
    final stamp = time == null ? e.time : DateFormat('MMM d, h:mm a').format(time);
    final meta = <String>[
      if (_seesAll && e.userName.isNotEmpty) '${e.userName} (${_capitalize(e.role)})',
      if (e.ip != null) e.ip!,
      if (e.device != null) e.device!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconBubble(style),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [_badge(style), Text(stamp, style: const TextStyle(fontSize: 11, color: _Ui.muted))],
                ),
                const SizedBox(height: 6),
                Text(e.details, style: const TextStyle(fontSize: 13, color: _Ui.ink)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(meta, style: const TextStyle(fontSize: 11, color: _Ui.muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- shared cells ----

  Widget _iconBubble(_KindStyle style) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: style.color.withOpacity(0.12), shape: BoxShape.circle),
      child: Icon(style.icon, size: 18, color: style.color),
    );
  }

  Widget _badge(_KindStyle style) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: style.color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(style.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: style.color)),
    );
  }

  Widget _dateCell(ActivityLogEntry e) {
    final time = _parseTime(e.time);
    if (time == null) return Text(e.time, style: const TextStyle(fontSize: 12, color: _Ui.ink));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(DateFormat('MMM d, yyyy').format(time), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _Ui.ink)),
        Text(DateFormat('h:mm a').format(time), style: const TextStyle(fontSize: 11, color: _Ui.muted)),
      ],
    );
  }

  Widget _userCell(ActivityLogEntry e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(e.userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _Ui.ink)),
        Text(_capitalize(e.role), style: const TextStyle(fontSize: 11, color: _Ui.muted)),
      ],
    );
  }

  Widget _deviceCell(ActivityLogEntry e) {
    if (e.device == null) return const Text('—', style: TextStyle(fontSize: 12, color: _Ui.ink));
    return Row(
      children: [
        Icon(_deviceIcon(e.device), size: 16, color: _Ui.muted),
        const SizedBox(width: 6),
        Flexible(child: Text(e.device!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _Ui.ink))),
      ],
    );
  }

  // ---- pagination ----

  Widget _pagination() {
    final start = (_page - 1) * _limit + 1;
    final end = (_page * _limit).clamp(0, _total);

    final first = (_page - 2).clamp(1, _pageCount);
    final last = (_page + 2).clamp(1, _pageCount);

    Widget pageButton(int p) {
      final selected = p == _page;
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Material(
          color: selected ? _Ui.tanDeep : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _goToPage(p),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              child: Text('$p', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : _Ui.ink)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text('Showing $start-$end of $_total activities', style: const TextStyle(fontSize: 12, color: _Ui.muted)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous page',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _page > 1 ? () => _goToPage(_page - 1) : null,
              ),
              for (var p = first; p <= last; p++) pageButton(p),
              IconButton(
                tooltip: 'Next page',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: _page < _pageCount ? () => _goToPage(_page + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}