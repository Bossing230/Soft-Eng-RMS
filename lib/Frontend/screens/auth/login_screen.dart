import 'package:flutter/material.dart';
import 'package:rms/Frontend/services/api_services.dart';
import 'package:rms/Frontend/services/auth_services.dart';
import '../../core/routes/app_router.dart';
import 'forgot_password_page.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  /// Set only while the account is actually locked, so the form and the
  /// "Forgot password?" link can reflect it without a repeat popup on every
  /// attempt — the popup itself only ever appears once, right when the lock
  /// is first triggered (see _handleLockout).
  DateTime? _lockedUntil;

  String _formatLockTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  void _openForgotPassword() {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your username first, then tap "Forgot password?" again.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ForgotPasswordPage(username: username)),
    );
  }

  /// Shown exactly once, the moment the 3rd wrong password actually triggers
  /// a new lock (the server says justLocked: true) — not on every subsequent
  /// attempt while already locked, which would just be repetitive.
  Future<void> _showJustLockedDialog(int lockoutMinutes) async {
    final durationText = lockoutMinutes >= 60 ? '${(lockoutMinutes / 60).round()} hour(s)' : '$lockoutMinutes minute(s)';
    final wantsReset = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Too many failed attempts'),
        content: Text(
          'This account is locked for $durationText after 3 incorrect passwords.\n\n'
          'Would you like to reset your password instead of waiting?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, reset it')),
        ],
      ),
    );
    if (wantsReset == true && mounted) _openForgotPassword();
  }

  void _handleLockout(ApiException e) {
    final body = e.body ?? {};
    final lockedUntilStr = body['lockedUntil'] as String?;
    final lockoutMinutes = (body['lockoutMinutes'] as num?)?.toInt() ?? 0;
    final justLocked = body['justLocked'] == true;
    final lockedUntil = lockedUntilStr != null ? DateTime.tryParse(lockedUntilStr) : null;

    setState(() {
      _lockedUntil = lockedUntil;
      _error = lockedUntil != null
          ? 'Account locked until ${_formatLockTime(lockedUntil.toLocal())}.'
          : e.message;
    });

    if (justLocked) _showJustLockedDialog(lockoutMinutes);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _authService.login(_usernameController.text.trim(), _passwordController.text);
      if (!mounted) return;
      AppRouter.goToRoleDashboard(context);
    } on ApiException catch (e) {
      if (e.statusCode == 423) {
        _handleLockout(e);
      } else {
        final remaining = (e.body?['attemptsRemaining'] as num?)?.toInt();
        setState(() {
          _lockedUntil = null;
          _error = remaining != null ? '${e.message} ($remaining attempt(s) remaining)' : e.message;
        });
      }
    } catch (e) {
      setState(() => _error = 'Could not reach the server. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = _lockedUntil != null;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The two logos live in their own Row, nested as a
                  // single item inside this outer Column — they are not
                  // the whole form's layout.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset('assets/images/ics_logo.png', height: 100),
                      const SizedBox(width: 16),
                      Image.asset('assets/images/tcgc_logo.png', height: 100),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Restaurant Management System',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Username is required' : null,
                    onChanged: (_) {
                      // A fresh username means the previous lock message no longer applies to what's being typed.
                      if (_lockedUntil != null) setState(() => _lockedUntil = null);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    enabled: !isLocked,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: (_loading || isLocked) ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Log In'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _openForgotPassword,
                    child: const Text('Forgot password?'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This is an internal system. Contact your administrator if you need an account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}