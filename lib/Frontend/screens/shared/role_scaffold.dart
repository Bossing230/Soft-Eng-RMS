import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/notification.dart';
import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import 'package:rms/Frontend/services/auth_services.dart';
import '../../core/routes/app_router.dart';
import '../../core/constants/app_constants.dart';
import '../../repositories/notification_repository.dart';
import 'account_settings_page.dart';
import 'activity_log_page.dart';

class RoleNavItem {
  final String label;
  final IconData icon;
  final Widget page;

  /// What the top bar shows while this tab is open. Defaults to [label] when
  /// not given — only set this where the page's heading differs from its
  /// short sidebar label (for example label 'POS', pageTitle 'Point of Sale').
  final String? pageTitle;

  const RoleNavItem({required this.label, required this.icon, required this.page, this.pageTitle});
}

/// Carries the "switch to another tab" action down to whatever page is
/// currently open inside a [RoleScaffold], so that page can jump to a
/// sibling tab (e.g. a "View orders" quick action) without Navigator routes.
class _RoleScaffoldScope extends InheritedWidget {
  final void Function(String label) goToLabel;
  const _RoleScaffoldScope({required this.goToLabel, required super.child});

  static _RoleScaffoldScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RoleScaffoldScope>();

  @override
  bool updateShouldNotify(_RoleScaffoldScope oldWidget) => goToLabel != oldWidget.goToLabel;
}

/// Lets a page hosted inside [RoleScaffold] switch to a sibling tab by its
/// sidebar label, e.g. `RoleScaffoldNavigator.goTo(context, 'Orders')`.
/// Does nothing if there is no enclosing [RoleScaffold], or no tab with
/// that label.
class RoleScaffoldNavigator {
  RoleScaffoldNavigator._();

  static void goTo(BuildContext context, String label) {
    _RoleScaffoldScope.of(context)?.goToLabel(label);
  }
}

class RoleScaffold extends StatefulWidget {
  final String title;
  final List<RoleNavItem> items;

  const RoleScaffold({super.key, required this.title, required this.items});

  @override
  State<RoleScaffold> createState() => _RoleScaffoldState();
}

class _RoleScaffoldState extends State<RoleScaffold> {
  int _selected = 0;
  final _notificationRepo = NotificationRepository();
  List<NotificationItem> _notifications = [];
  Timer? _pollTimer;

  /// True while the avatar dropdown is showing, so its caret can point up.
  bool _accountMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadNotifications());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    try {
      final data = await _notificationRepo.getAll();
      if (mounted) setState(() => _notifications = data);
    } catch (_) {}
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Each tab's own heading: its pageTitle if it set one (e.g. the dashboard/
  /// summary tab uses "<Role> Dashboard"), otherwise its sidebar label —
  /// matching how every page design in this app labels its own top bar.
  String get _topTitle {
    final item = widget.items[_selected];
    return item.pageTitle ?? item.label;
  }

  /// Opens one of the sidebar / bottom-bar tabs.
  void _selectTab(int index) {
    setState(() => _selected = index);
  }

  /// Opens an account-menu page as its own full screen (red top bar with a
  /// back arrow, no sidebar), the same way the "New Menu Item" page opens.
  void _openFullPage(String title, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: page,
        ),
      ),
    );
  }

  void _openActivityLog() => _openFullPage('Activity Log', const ActivityLogPage());

  /// [section] is 'profile', 'password' or 'delete'.
  void _openAccountSettings(String section) {
    const titles = {
      'profile': 'My Profile',
      'password': 'Change Password',
      'delete': 'Delete Account',
    };
    _openFullPage(
      titles[section] ?? 'My Profile',
      AccountSettingsPage(
        initialSection: section,
        // The name or photo changed: rebuild so the dashboard top bar shows it.
        onProfileChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  String get _initials {
    final name = SessionManager().name?.trim() ?? '';
    if (name.isEmpty) return SessionManager().username?.substring(0, 1).toUpperCase() ?? '?';
    final parts = name.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts.first[0].toUpperCase();
  }

  String? get _fullPhotoUrl {
    final path = SessionManager().profileImage;
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    final base = AppConstants.apiBaseUrl.replaceAll('/api', '');
    return '$base$path';
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService().logout();
      if (mounted) AppRouter.goToLogin(context);
    }
  }

  Widget _sidebarContent({required bool isDrawer}) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/ics_logo.png', height: 48),
            const SizedBox(width: 10),
            Image.asset('assets/images/tcgc_logo.png', height: 48),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            AppConstants.appName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
        const SizedBox(height: 28),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: widget.items.length,
            itemBuilder: (_, i) {
              final item = widget.items[i];
              final selected = i == _selected;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                child: ListTile(
                  leading: Icon(item.icon, color: selected ? primary : Colors.grey[700]),
                  title: Text(item.label, style: TextStyle(color: selected ? primary : Colors.black87, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                  selected: selected,
                  selectedTileColor: primary.withOpacity(0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onTap: () {
                    _selectTab(i);
                    if (isDrawer) Navigator.of(context).maybePop();
                  },
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Log Out'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red[700], side: BorderSide(color: Colors.red[200]!)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _notificationBell() {
    return PopupMenuButton<int>(
      tooltip: 'Notifications',
      onSelected: (id) async {
        await _notificationRepo.markRead(id);
        _loadNotifications();
      },
      icon: Badge(
        isLabelVisible: _unreadCount > 0,
        label: Text('$_unreadCount'),
        child: const Icon(Icons.notifications_outlined),
      ),
      itemBuilder: (ctx) {
        if (_notifications.isEmpty) {
          return [const PopupMenuItem(enabled: false, child: Text('No notifications yet'))];
        }
        return [
          PopupMenuItem(
            enabled: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () async {
                    await _notificationRepo.markAllRead();
                    _loadNotifications();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Mark all read', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          ..._notifications.take(10).map((n) => PopupMenuItem<int>(
                value: n.notificationId,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold, fontSize: 13)),
                  subtitle: Text(n.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ),
              )),
        ];
      },
    );
  }

  Widget _avatarMenu() {
    final session = SessionManager();
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      // The caret points up while the menu is open, down when it is closed.
      onOpened: () => setState(() => _accountMenuOpen = true),
      onCanceled: () => setState(() => _accountMenuOpen = false),
      onSelected: (value) {
        setState(() => _accountMenuOpen = false);
        switch (value) {
          case 'profile':
            _openAccountSettings('profile');
            break;
          case 'password':
            _openAccountSettings('password');
            break;
          case 'activity':
            _openActivityLog();
            break;
          case 'delete':
            _openAccountSettings('delete');
            break;
          case 'logout':
            _confirmLogout();
            break;
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          enabled: false,
          child: SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundImage: _fullPhotoUrl != null ? NetworkImage(_fullPhotoUrl!) : null,
                  child: _fullPhotoUrl == null ? Text(_initials, style: const TextStyle(fontSize: 28)) : null,
                ),
                const SizedBox(height: 14),
                Text(
                  session.name ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  session.email ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  session.role ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.person_outline, size: 18), SizedBox(width: 12), Text('My Profile')])),
        const PopupMenuItem(value: 'password', child: Row(children: [Icon(Icons.lock_outline, size: 18), SizedBox(width: 12), Text('Change Password')])),
        const PopupMenuItem(value: 'activity', child: Row(children: [Icon(Icons.history, size: 18), SizedBox(width: 12), Text('Activity Log')])),
        const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 12), Text('Delete Account', style: TextStyle(color: Colors.red))])),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, size: 18, color: Colors.red), SizedBox(width: 12), Text('Logout', style: TextStyle(color: Colors.red))])),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
            backgroundImage: _fullPhotoUrl != null ? NetworkImage(_fullPhotoUrl!) : null,
            child: _fullPhotoUrl == null
                ? Text(_initials, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))
                : null,
          ),
          AnimatedRotation(
            turns: _accountMenuOpen ? 0.5 : 0, // 0.5 turn = caret flipped up
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.arrow_drop_down, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Text(_topTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const Spacer(),
          _notificationBell(),
          const SizedBox(width: 12),
          _avatarMenu(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;
    final body = _RoleScaffoldScope(
      goToLabel: (label) {
        final index = widget.items.indexWhere((i) => i.label == label);
        if (index != -1) _selectTab(index);
      },
      child: widget.items[_selected].page,
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 260, child: Material(elevation: 1, child: _sidebarContent(isDrawer: false))),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  _topBar(),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_topTitle),
        actions: [
          _notificationBell(),
          const SizedBox(width: 8),
          _avatarMenu(),
          const SizedBox(width: 12),
        ],
      ),
      drawer: Drawer(child: SafeArea(child: _sidebarContent(isDrawer: true))),
      body: body,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selected,
        type: BottomNavigationBarType.fixed,
        onTap: _selectTab,
        items: widget.items.map((item) => BottomNavigationBarItem(icon: Icon(item.icon), label: item.label)).toList(),
      ),
    );
  }
}