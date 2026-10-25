import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rms/Frontend/services/api_services.dart';
import 'package:rms/Frontend/widgets/otp_boxes.dart';
import '../../repositories/employee_repository.dart';
import '../../models/employee.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

class EmployeeManagementPage extends StatefulWidget {
  const EmployeeManagementPage({super.key});

  @override
  State<EmployeeManagementPage> createState() => _EmployeeManagementPageState();
}

class _EmployeeManagementPageState extends State<EmployeeManagementPage> {
  final _repo = EmployeeRepository();
  List<Employee> _employees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _repo.getAll();
    setState(() {
      _employees = data;
      _loading = false;
    });
  }

  String _fullImageUrl(String path) {
    if (path.startsWith('http')) return path;
    final base = AppConstants.apiBaseUrl.replaceAll('/api', '');
    return '$base$path';
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'administrator':
        return Colors.red;
      case 'manager':
        return Colors.indigo;
      case 'cashier':
        return Colors.teal;
      case 'kitchen':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  // Shows a read-only detail card for one employee: large photo, email,
  // role, status — and a "Reset Password" action instead of ever
  // displaying the actual password, which is hashed and unrecoverable.
  void _showDetail(Employee e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // lets the sheet grow and scroll instead of clipping
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundImage: e.profileImage != null ? NetworkImage(_fullImageUrl(e.profileImage!)) : null,
                child: e.profileImage == null
                    ? Text(e.name.isNotEmpty ? e.name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 32))
                    : null,
              ),
              const SizedBox(height: 16),
              Text(e.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Chip(
                label: Text(e.role, style: const TextStyle(color: Colors.white, fontSize: 12)),
                backgroundColor: _roleColor(e.role),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(height: 24),
              _DetailRow(icon: Icons.alternate_email, label: 'Username', value: e.username),
              const SizedBox(height: 14),
              _DetailRow(icon: Icons.mail_outline, label: 'Email', value: e.email),
              const SizedBox(height: 14),
              _DetailRow(
                icon: e.status == 'active' ? Icons.check_circle_outline : Icons.pause_circle_outline,
                label: 'Status',
                value: e.status == 'active' ? 'Active' : 'Deactivated',
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Passwords are encrypted and can\'t be viewed by anyone, including administrators. '
                'Use the button below to set a new one if this employee needs it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showResetPasswordDialog(e);
                  },
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('Reset Password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showResetPasswordDialog(Employee e) async {
    final newPasswordCtrl = TextEditingController();
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Reset password for ${e.name}'),
          content: TextField(
            controller: newPasswordCtrl,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New temporary password'),
          ),
          actions: [
            TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (newPasswordCtrl.text.trim().length < 6) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters')));
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        await _repo.resetPassword(e.employeeId, newPasswordCtrl.text.trim());
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset successfully')));
                        }
                      } catch (err) {
                        setDialogState(() => submitting = false);
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: $err')));
                      }
                    },
              child: submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateEmployeeDialog(repo: _repo),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Employee'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _employees.length,
                itemBuilder: (_, i) {
                  final e = _employees[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        onTap: () => _showDetail(e),
                        leading: CircleAvatar(
                          backgroundImage: e.profileImage != null ? NetworkImage(_fullImageUrl(e.profileImage!)) : null,
                          child: e.profileImage == null ? Text(e.name.isNotEmpty ? e.name[0].toUpperCase() : '?') : null,
                        ),
                        title: Text(e.name),
                        subtitle: Text('${e.username} • ${e.role}'),
                        trailing: Switch(
                          value: e.status == 'active',
                          onChanged: (val) async {
                            await _repo.setStatus(e.employeeId, val);
                            _load();
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// New employee dialog, with email verification right under the Email field:
//   editing   -> type the email, "Send verification code" appears once valid
//   codeSent  -> 6 code boxes + resend countdown, checked automatically
//   verified  -> email locked with a green check; Create becomes available
// The server also requires the verification token when creating the account,
// so this can't be skipped by calling the API directly.
// ---------------------------------------------------------------------------

enum _EmailStage { editing, codeSent, verified }

class _CreateEmployeeDialog extends StatefulWidget {
  final EmployeeRepository repo;
  const _CreateEmployeeDialog({required this.repo});

  @override
  State<_CreateEmployeeDialog> createState() => _CreateEmployeeDialogState();
}

class _CreateEmployeeDialogState extends State<_CreateEmployeeDialog> {
  final _firstCtrl = TextEditingController();
  final _middleCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _role = AppConstants.roleCashier;

  XFile? _pickedPhoto;
  Uint8List? _previewBytes;
  bool _submitting = false;
  bool _obscurePassword = true;

  _EmailStage _stage = _EmailStage.editing;
  bool _emailBusy = false;
  String? _emailError;
  String _maskedEmail = '';
  String _emailToken = '';
  String _verifiedEmail = '';
  String _code = '';
  int _codeGen = 0;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _firstCtrl.dispose();
    _middleCtrl.dispose();
    _lastCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------- email check

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldown -= 1;
        if (_cooldown <= 0) {
          _cooldown = 0;
          t.cancel();
        }
      });
    });
  }

  String _friendly(Object e) => e is TimeoutException
      ? 'The server is taking too long to respond. Please try again.'
      : 'Could not reach the server. Check your connection and try again.';

  Future<void> _sendCode() async {
    if (_emailBusy) return;
    final email = _emailCtrl.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _emailError = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _emailBusy = true;
      _emailError = null;
    });
    try {
      final masked = await widget.repo.requestEmailCode(email);
      if (!mounted) return;
      setState(() {
        _maskedEmail = masked;
        _stage = _EmailStage.codeSent;
        _code = '';
        _codeGen++;
      });
      _startCooldown(60);
    } on ApiException catch (e) {
      final retry = e.body?['retryAfterSeconds'];
      final masked = e.body?['maskedEmail'] as String?;
      if (retry is int && masked != null) {
        // An earlier code is still valid: go enter it and respect the cooldown.
        setState(() {
          _maskedEmail = masked;
          _stage = _EmailStage.codeSent;
          _code = '';
          _codeGen++;
        });
        _startCooldown(retry);
      } else {
        setState(() => _emailError = e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _emailError = _friendly(e));
    } finally {
      if (mounted) setState(() => _emailBusy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_emailBusy || _code.length != 6) return;
    setState(() {
      _emailBusy = true;
      _emailError = null;
    });
    try {
      final email = _emailCtrl.text.trim();
      final token = await widget.repo.verifyEmailCode(email, _code);
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _emailToken = token;
        _verifiedEmail = email;
        _cooldown = 0;
        _stage = _EmailStage.verified;
      });
    } on ApiException catch (e) {
      setState(() {
        _emailError = e.message;
        _code = '';
        _codeGen++; // clear the boxes so a wrong code isn't re-sent by accident
      });
    } catch (e) {
      if (mounted) setState(() => _emailError = _friendly(e));
    } finally {
      if (mounted) setState(() => _emailBusy = false);
    }
  }

  /// Unlocks the email field and throws away any verification.
  void _changeEmail() {
    _timer?.cancel();
    setState(() {
      _stage = _EmailStage.editing;
      _emailToken = '';
      _verifiedEmail = '';
      _code = '';
      _cooldown = 0;
      _emailError = null;
    });
  }

  // --------------------------------------------------------------- create

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _pickedPhoto = file;
        _previewBytes = bytes;
      });
    }
  }

  Future<void> _create() async {
    if (_firstCtrl.text.trim().isEmpty ||
        _lastCtrl.text.trim().isEmpty ||
        _usernameCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('First name, last name, username, and password are required')));
      return;
    }
    if (_stage != _EmailStage.verified) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verify the email address first')));
      return;
    }
    setState(() => _submitting = true);
    try {
      String? photoUrl;
      if (_previewBytes != null && _pickedPhoto != null) {
        photoUrl = await widget.repo.uploadPhoto(bytes: _previewBytes!, filename: _pickedPhoto!.name);
      }
      // The database stores one name, so the three parts are joined: "First Middle Last".
      final fullName = [_firstCtrl.text, _middleCtrl.text, _lastCtrl.text]
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .join(' ');
      await widget.repo.create(
        name: fullName,
        username: _usernameCtrl.text.trim(),
        email: _verifiedEmail,
        emailToken: _emailToken,
        password: _passwordCtrl.text,
        role: _role,
        profileImage: photoUrl,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (e.statusCode == 403) {
          // The verification expired or didn't match: ask for it again.
          _stage = _EmailStage.editing;
          _emailToken = '';
          _verifiedEmail = '';
          _emailError = e.message;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create: $e')));
    }
  }

  // ------------------------------------------------------------------- UI

  ButtonStyle get _linkStyle => ButtonStyle(
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        backgroundColor: WidgetStateProperty.all(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
        minimumSize: WidgetStateProperty.all(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? Colors.black26
              : (s.contains(WidgetState.hovered) ? AppTheme.primary : Colors.black54),
        ),
        textStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 13,
            decoration: s.contains(WidgetState.hovered) ? TextDecoration.underline : TextDecoration.none,
          ),
        ),
      );

  String _fmt(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  Widget _emailSection() {
    final locked = _stage != _EmailStage.editing;
    final verified = _stage == _EmailStage.verified;
    final emailValid = _emailRe.hasMatch(_emailCtrl.text.trim());
    final errorColor = Theme.of(context).colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailCtrl,
          readOnly: locked,
          enabled: !_submitting,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() => _emailError = null),
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.mail_outline),
            suffixIcon: verified ? const Icon(Icons.verified, color: Colors.green) : null,
          ),
        ),
        if (_stage == _EmailStage.editing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: (_emailBusy || !emailValid) ? null : _sendCode,
              child: _emailBusy
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Sending...'),
                      ],
                    )
                  : const Text('Send verification code'),
            ),
          ),
        if (_stage == _EmailStage.codeSent) ...[
          const SizedBox(height: 12),
          Text('Enter the 6-digit code sent to $_maskedEmail', style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 10),
          Center(
            child: OtpBoxes(
              key: ValueKey(_codeGen),
              enabled: !_emailBusy,
              hasError: _emailError != null,
              onChanged: (v) => setState(() {
                _code = v;
                if (_emailError != null) _emailError = null;
              }),
              onCompleted: (v) {
                setState(() => _code = v);
                _verifyCode();
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(style: _linkStyle, onPressed: _emailBusy ? null : _changeEmail, child: const Text('Change email')),
              _cooldown > 0
                  ? Text('Resend code in ${_fmt(_cooldown)}', style: const TextStyle(fontSize: 13, color: Colors.black45))
                  : TextButton(style: _linkStyle, onPressed: _emailBusy ? null : _sendCode, child: const Text('Resend code')),
            ],
          ),
        ],
        if (verified)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.green),
                    SizedBox(width: 6),
                    Text('Email verified', style: TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.w600)),
                  ],
                ),
                TextButton(style: _linkStyle, onPressed: _submitting ? null : _changeEmail, child: const Text('Change email')),
              ],
            ),
          ),
        if (_emailError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 16, color: errorColor),
                const SizedBox(width: 6),
                Expanded(child: Text(_emailError!, style: TextStyle(color: errorColor, fontSize: 13))),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = !_submitting && _stage == _EmailStage.verified;
    return AlertDialog(
      title: const Text('New Employee Account'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: GestureDetector(
                  onTap: _submitting ? null : _pickPhoto,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: _previewBytes != null ? MemoryImage(_previewBytes!) : null,
                        child: _previewBytes == null ? const Icon(Icons.person, size: 40, color: Colors.grey) : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _firstCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'First name', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _middleCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Middle name (optional)', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _lastCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Last name', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 16),
              TextField(controller: _usernameCtrl, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email))),
              const SizedBox(height: 16),
              _emailSection(),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Temporary password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(Icons.assignment_ind_outlined)),
                items: const [
                  DropdownMenuItem(value: AppConstants.roleManager, child: Text('Manager')),
                  DropdownMenuItem(value: AppConstants.roleCashier, child: Text('Cashier')),
                  DropdownMenuItem(value: AppConstants.roleKitchen, child: Text('Kitchen Staff')),
                ],
                onChanged: _submitting ? null : (v) => setState(() => _role = v!),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: canCreate ? _create : null,
          child: _submitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Create'),
        ),
      ],
    );
  }
}