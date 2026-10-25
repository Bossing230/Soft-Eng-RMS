import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/models/account_profile.dart';
import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import 'package:rms/Frontend/services/auth_services.dart';
import '../../core/constants/app_constants.dart';
import '../../repositories/account_repository.dart';

// ---------------------------------------------------------------------------
// Design tokens (the same warm palette as the Inventory and Activity Log pages).
// ---------------------------------------------------------------------------
class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const disabledFill = Color(0xFFF3EEE9);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
  static const red = Color(0xFFE53935);
}

enum _Section { profile, password, settings }

_Section _sectionFrom(String name) {
  for (final s in _Section.values) {
    if (s.name == name) return s;
  }
  return _Section.profile;
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0]).join().toUpperCase();
}

/// The photo URL to show: a full https link (Cloudinary), or a path on the server.
String? _photoUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http')) return path;
  final base = AppConstants.apiBaseUrl.replaceAll('/api', '');
  return '$base$path';
}

/// Account Settings: profile details and photo, change password, a link to the
/// Activity Log, and (for administrators and managers) the order rates.
/// Opened from the profile menu inside the dashboard, so it has no Scaffold.
class AccountSettingsPage extends StatefulWidget {
  /// 'profile', 'password' or 'settings'.
  final String initialSection;

  /// Opens the Activity Log page (the dashboard owns that navigation).
  final VoidCallback? onOpenActivityLog;

  /// Called after the name or photo changed, so the top bar can refresh.
  final VoidCallback? onProfileChanged;

  const AccountSettingsPage({
    super.key,
    this.initialSection = 'profile',
    this.onOpenActivityLog,
    this.onProfileChanged,
  });

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _repo = AccountRepository();

  late _Section _section;
  AccountProfile? _profile;
  bool _loading = true;
  String? _loadError;

  // profile form
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  String? _nameError;
  String? _phoneError;
  String? _addressError;
  bool _saving = false;
  bool _uploadingPhoto = false;

  // password form
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  String? _passwordError;
  bool _changingPassword = false;

  // settings
  Map<String, dynamic>? _rates;
  bool _ratesLoading = false;
  String? _ratesError;

  bool get _seesRates {
    final role = SessionManager().role;
    return role == AppConstants.roleAdmin || role == AppConstants.roleManager;
  }

  bool get _dirty {
    final p = _profile;
    if (p == null) return false;
    return _name.text.trim() != p.name || _phone.text.trim() != p.phone || _address.text.trim() != p.address;
  }

  @override
  void initState() {
    super.initState();
    _section = _sectionFrom(widget.initialSection);
    _loadProfile();
    if (_section == _Section.settings) _loadRates();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- loading ----

  void _fill(AccountProfile p) {
    _name.text = p.name;
    _phone.text = p.phone;
    _address.text = p.address;
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final profile = await _repo.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _fill(profile);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadRates() async {
    if (!_seesRates || _rates != null || _ratesLoading) return;
    setState(() {
      _ratesLoading = true;
      _ratesError = null;
    });
    try {
      final rates = await _repo.getOrderRates();
      if (!mounted) return;
      setState(() {
        _rates = rates;
        _ratesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ratesError = '$e';
        _ratesLoading = false;
      });
    }
  }

  void _select(_Section section) {
    setState(() => _section = section);
    if (section == _Section.settings) _loadRates();
  }

  // ---- profile actions ----

  Future<void> _saveProfile() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final address = _address.text.trim();

    String? nameError;
    String? phoneError;
    String? addressError;
    if (name.length < 2) nameError = 'Enter your full name';
    if (name.length > 100) nameError = 'Name must be 100 characters or fewer';
    if (phone.isNotEmpty && !RegExp(r'^[0-9+\-\s()]{7,20}$').hasMatch(phone)) {
      phoneError = 'Use digits, spaces and + - ( ) only (7 to 20 characters)';
    }
    if (address.length > 255) addressError = 'Address must be 255 characters or fewer';

    setState(() {
      _nameError = nameError;
      _phoneError = phoneError;
      _addressError = addressError;
    });
    if (nameError != null || phoneError != null || addressError != null) return;

    setState(() => _saving = true);
    try {
      final updated = await _repo.updateProfile(name: name, phone: phone, address: address);
      await SessionManager().updateProfile(name: updated.name);
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _fill(updated);
      });
      widget.onProfileChanged?.call();
      _snack('Profile updated');
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    if (_uploadingPhoto) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (file == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await _repo.uploadPhoto(bytes: bytes, filename: file.name);
      await SessionManager().updateProfile(profileImage: url);
      if (!mounted) return;
      setState(() => _profile = _profile?.copyWith(profileImage: url));
      widget.onProfileChanged?.call();
      _snack('Photo updated');
    } catch (e) {
      _snack('Could not update the photo: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ---- password action ----

  Future<void> _changePassword() async {
    final current = _currentPassword.text;
    final next = _newPassword.text.trim();
    final confirm = _confirmPassword.text.trim();

    String? error;
    if (current.isEmpty) {
      error = 'Enter your current password';
    } else if (next.length < 6) {
      error = 'New password must be at least 6 characters';
    } else if (next != confirm) {
      error = 'The new passwords do not match';
    } else if (next == current) {
      error = 'Choose a password different from your current one';
    }
    if (error != null) {
      setState(() => _passwordError = error);
      return;
    }

    setState(() {
      _changingPassword = true;
      _passwordError = null;
    });
    try {
      await AuthService().changePassword(current, next);
      if (!mounted) return;
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      _snack('Password changed successfully');
    } catch (e) {
      if (mounted) setState(() => _passwordError = '$e');
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40, color: _Ui.muted),
              const SizedBox(height: 12),
              const Text("Couldn't load your account", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(_loadError ?? 'Something went wrong.', textAlign: TextAlign.center, style: const TextStyle(color: _Ui.muted)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadProfile, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final content = _contentCard();
        final menu = _menuCard();
        return SingleChildScrollView(
          padding: EdgeInsets.all(wide ? 24 : 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Account Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _Ui.ink)),
                  const SizedBox(height: 2),
                  const Text('Manage your profile and account preferences.', style: TextStyle(fontSize: 13, color: _Ui.muted)),
                  const SizedBox(height: 18),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: content),
                        const SizedBox(width: 16),
                        SizedBox(width: 340, child: menu),
                      ],
                    )
                  else ...[
                    menu,
                    const SizedBox(height: 16),
                    content,
                  ],
                  const SizedBox(height: 16),
                  _quickInfo(_profile!),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- shared pieces ----

  Widget _card({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(20)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _Ui.border)),
      child: child,
    );
  }

  Widget _cardHeader(IconData icon, String title, String subtitle) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: primary.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 20, color: primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _Ui.ink)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: _Ui.muted)),
            ],
          ),
        ),
      ],
    );
  }

  /// A small label above a field, as in the design.
  Widget _labeled(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _Ui.ink)),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  InputDecoration _decoration({String? error, bool disabled = false, Widget? suffix}) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: disabled ? _Ui.disabledFill : Colors.white,
      errorText: error,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _Ui.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _Ui.border)),
      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _Ui.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
    );
  }

  Widget _primaryButton({required String label, required IconData icon, required bool busy, required VoidCallback? onPressed}) {
    return ElevatedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(icon, size: 18),
      label: Text(label),
    );
  }

  // ---- right-hand menu ----

  Widget _menuCard() {
    final items = <Widget>[
      _menuItem(Icons.person_outline, 'Profile', 'View and edit your profile information',
          selected: _section == _Section.profile, onTap: () => _select(_Section.profile)),
      _menuItem(Icons.lock_outline, 'Change Password', 'Update your account password',
          selected: _section == _Section.password, onTap: () => _select(_Section.password)),
      _menuItem(Icons.history, 'Activity Log', 'View your recent activities',
          selected: false, onTap: widget.onOpenActivityLog),
      _menuItem(Icons.settings_outlined, 'Account Settings', 'Manage your preferences and system settings',
          selected: _section == _Section.settings, onTap: () => _select(_Section.settings)),
    ];
    return _card(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String title, String subtitle, {required bool selected, required VoidCallback? onTap}) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: selected ? primary.withOpacity(0.10) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: primary.withOpacity(selected ? 0.18 : 0.08), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 19, color: primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: _Ui.ink)),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: _Ui.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: _Ui.muted),
            ],
          ),
        ),
      ),
    );
  }

  // ---- left-hand content ----

  Widget _contentCard() {
    switch (_section) {
      case _Section.profile:
        return _profileCard();
      case _Section.password:
        return _passwordCard();
      case _Section.settings:
        return _settingsCard();
    }
  }

  Widget _profileCard() {
    final p = _profile!;

    final photoColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _avatar(p),
        const SizedBox(height: 14),
        Text(p.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _Ui.ink)),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mail_outline, size: 14, color: _Ui.muted),
            const SizedBox(width: 6),
            Flexible(child: Text(p.email, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _Ui.muted))),
          ],
        ),
        const SizedBox(height: 10),
        _roleChip(p.role),
      ],
    );

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _labeled(
          'Full Name',
          TextField(
            controller: _name,
            enabled: !_saving,
            onChanged: (_) => setState(() => _nameError = null),
            decoration: _decoration(error: _nameError),
          ),
        ),
        const SizedBox(height: 14),
        _labeled(
          'Email Address',
          TextFormField(
            initialValue: p.email,
            enabled: false,
            decoration: _decoration(disabled: true),
          ),
        ),
        const SizedBox(height: 14),
        _labeled(
          'Position',
          TextFormField(
            initialValue: _capitalize(p.role),
            enabled: false,
            decoration: _decoration(disabled: true, suffix: const Icon(Icons.lock_outline, size: 16, color: _Ui.muted)),
          ),
        ),
        const SizedBox(height: 14),
        _labeled(
          'Phone Number',
          TextField(
            controller: _phone,
            enabled: !_saving,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() => _phoneError = null),
            decoration: _decoration(error: _phoneError),
          ),
        ),
        const SizedBox(height: 14),
        _labeled(
          'Address',
          TextField(
            controller: _address,
            enabled: !_saving,
            maxLines: 2,
            onChanged: (_) => setState(() => _addressError = null),
            decoration: _decoration(error: _addressError),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your email and position are managed by an administrator.',
          style: TextStyle(fontSize: 11.5, color: _Ui.muted),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: _primaryButton(
            label: 'Save Changes',
            icon: Icons.save_outlined,
            busy: _saving,
            onPressed: _dirty ? _saveProfile : null,
          ),
        ),
      ],
    );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.person_outline, 'Profile Information', 'Update your personal information.'),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 560) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 200, child: photoColumn),
                    const SizedBox(width: 24),
                    Expanded(child: form),
                  ],
                );
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: photoColumn), const SizedBox(height: 20), form]);
            },
          ),
        ],
      ),
    );
  }

  Widget _avatar(AccountProfile p) {
    final primary = Theme.of(context).colorScheme.primary;
    final url = _photoUrl(p.profileImage);
    return SizedBox(
      width: 118,
      height: 118,
      child: Stack(
        children: [
          Container(
            width: 112,
            height: 112,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primary.withOpacity(0.35), width: 2)),
            child: CircleAvatar(
              backgroundColor: primary.withOpacity(0.12),
              backgroundImage: url != null ? NetworkImage(url) : null,
              child: url == null ? Text(_initialsOf(p.name), style: TextStyle(fontSize: 34, color: primary)) : null,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 4,
            child: Material(
              color: primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _uploadingPhoto ? null : _pickPhoto,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _uploadingPhoto
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.photo_camera, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleChip(String role) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(color: primary.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(_capitalize(role), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary)),
    );
  }

  Widget _passwordCard() {
    Widget eye(bool shown, VoidCallback toggle) => IconButton(
          icon: Icon(shown ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: _Ui.muted),
          onPressed: toggle,
        );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(Icons.lock_outline, 'Change Password', 'Update your account password.'),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _labeled(
                  'Current Password',
                  TextField(
                    controller: _currentPassword,
                    obscureText: !_showCurrent,
                    enabled: !_changingPassword,
                    onChanged: (_) => setState(() => _passwordError = null),
                    decoration: _decoration(suffix: eye(_showCurrent, () => setState(() => _showCurrent = !_showCurrent))),
                  ),
                ),
                const SizedBox(height: 14),
                _labeled(
                  'New Password',
                  TextField(
                    controller: _newPassword,
                    obscureText: !_showNew,
                    enabled: !_changingPassword,
                    onChanged: (_) => setState(() => _passwordError = null),
                    decoration: _decoration(suffix: eye(_showNew, () => setState(() => _showNew = !_showNew))),
                  ),
                ),
                const SizedBox(height: 14),
                _labeled(
                  'Confirm New Password',
                  TextField(
                    controller: _confirmPassword,
                    obscureText: !_showNew,
                    enabled: !_changingPassword,
                    onChanged: (_) => setState(() => _passwordError = null),
                    onSubmitted: (_) => _changePassword(),
                    decoration: _decoration(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Use at least 6 characters.', style: TextStyle(fontSize: 11.5, color: _Ui.muted)),
                if (_passwordError != null) ...[
                  const SizedBox(height: 10),
                  Text(_passwordError!, style: const TextStyle(fontSize: 13, color: _Ui.red)),
                ],
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _primaryButton(label: 'Update Password', icon: Icons.lock_reset, busy: _changingPassword, onPressed: _changePassword),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsCard() {
    Widget body;
    if (!_seesRates) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text('There are no preferences to change yet.', style: TextStyle(color: _Ui.muted)),
        ),
      );
    } else if (_ratesLoading) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Center(child: CircularProgressIndicator()));
    } else if (_ratesError != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(child: Text("Couldn't load the order rates: $_ratesError", style: const TextStyle(color: _Ui.muted))),
            TextButton(onPressed: _loadRates, child: const Text('Retry')),
          ],
        ),
      );
    } else if (_rates == null) {
      body = const SizedBox.shrink();
    } else {
      String percent(dynamic v) {
        final value = (double.tryParse('$v') ?? 0) * 100;
        return '${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1)}%';
      }

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Order rates', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Ui.ink)),
          const SizedBox(height: 4),
          const Text(
            'Added to every order at checkout. These are set in the server configuration.',
            style: TextStyle(fontSize: 12, color: _Ui.muted),
          ),
          const SizedBox(height: 14),
          _rateRow('Tax rate', percent(_rates!['taxRate'])),
          const SizedBox(height: 8),
          _rateRow('Service charge', percent(_rates!['serviceChargeRate'])),
        ],
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(Icons.settings_outlined, 'Account Settings', 'Your preferences and system settings.'),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }

  Widget _rateRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: _Ui.disabledFill, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: _Ui.ink))),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _Ui.ink)),
        ],
      ),
    );
  }

  // ---- quick info ----

  Widget _quickInfo(AccountProfile p) {
    final login = p.lastLogin == null ? null : DateTime.tryParse(p.lastLogin!.replaceFirst(' ', 'T'));
    final lastLogin = login == null ? '—' : DateFormat('MMM d, yyyy · h:mm a').format(login);

    final tiles = <Widget>[
      _infoTile(Icons.person_outline, 'Name', p.name),
      _infoTile(Icons.mail_outline, 'Email', p.email),
      _infoTile(Icons.work_outline, 'Position', _capitalize(p.role)),
      _infoTile(Icons.event_available_outlined, 'Last Login', lastLogin),
    ];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.shield_outlined, 'Quick Info', 'Your account details at a glance.'),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final columns = constraints.maxWidth >= 900 ? 4 : (constraints.maxWidth >= 520 ? 2 : 1);
              final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: tiles.map((t) => SizedBox(width: width, child: t)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _Ui.border)),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: primary.withOpacity(0.10), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11.5, color: _Ui.muted)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Ui.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}