import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/notification.dart';
import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import 'package:rms/Frontend/services/auth_services.dart';
import '../../core/routes/app_router.dart';
import '../../core/constants/app_constants.dart';
import '../../repositories/notification_repository.dart';

class RoleNavItem {
  final String label;
  final IconData icon;
  final Widget page;
  const RoleNavItem({required this.label, required this.icon, required this.page});
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

  void _showMyProfile() {
    final session = SessionManager();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundImage: _fullPhotoUrl != null ? NetworkImage(_fullPhotoUrl!) : null,
                child: _fullPhotoUrl == null ? Text(_initials, style: const TextStyle(fontSize: 28)) : null,
              ),
              const SizedBox(height: 16),
              Text(session.name ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(session.email ?? '', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 8),
              Chip(label: Text(session.role ?? ''), visualDensity: VisualDensity.compact),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: const Text('Username'),
                trailing: Text(session.username ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    bool submitting = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Change Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: currentCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
              const SizedBox(height: 16),
              TextField(controller: newCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (newCtrl.text.trim().length < 6) {
                        setDialogState(() => error = 'New password must be at least 6 characters');
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        await AuthService().changePassword(currentCtrl.text, newCtrl.text.trim());
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed successfully')));
                        }
                      } catch (e) {
                        setDialogState(() {
                          submitting = false;
                          error = 'Failed: $e';
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNotBuiltYet(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature isn\'t built yet — let me know if you want it added.')),
    );
  }

  // FIXED: this is a Column again (it had been accidentally changed to a
  // Row, which tried to lay the logo, nav list, and logout button out
  // side-by-side instead of stacked). The two logos now live in their
  // own small Row, nested as a single item inside this Column.
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
                    setState(() => _selected = i);
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
      onSelected: (value) {
        switch (value) {
          case 'profile':
            _showMyProfile();
            break;
          case 'password':
            _showChangePasswordDialog();
            break;
          case 'activity':
            _showNotBuiltYet('Activity Log');
            break;
          case 'settings':
            _showNotBuiltYet('Account Settings');
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
        const PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 12), Text('Account Settings')])),
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
          const Icon(Icons.arrow_drop_down, size: 18),
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
          Text('${widget.title} Dashboard', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
    final body = widget.items[_selected].page;

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
        title: Text('${widget.title} Dashboard'),
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
        onTap: (i) => setState(() => _selected = i),
        items: widget.items.map((item) => BottomNavigationBarItem(icon: Icon(item.icon), label: item.label)).toList(),
      ),
    );
  }
}