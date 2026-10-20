import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rms/Frontend/services/api_services.dart';
import 'package:rms/Frontend/services/auth_services.dart';

import '../../core/routes/app_router.dart';

enum _Step { email, code, newPassword, done }

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// The forgot-password flow: enter your email -> get a 6-digit code -> set a
/// new password -> straight into your dashboard. Reached from the "Forgot
/// password?" link on the login screen.
///
/// The code is always sent to the account's own email on file — the address
/// typed here is only ever used to look that account up, never as a
/// delivery address someone else could substitute — so this can't be used
/// to redirect a reset to an address an attacker controls.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _auth = AuthService();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  String? _error;
  String _email = '';
  String _maskedEmail = '';
  String _resetToken = '';
  String _confirmationNumber = '';
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  Timer? _autoContinueTimer;
  int _autoContinueSeconds = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _cooldownTimer?.cancel();
    _autoContinueTimer?.cancel();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown -= 1;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  void _goToDashboard() {
    _autoContinueTimer?.cancel();
    if (mounted) AppRouter.goToRoleDashboard(context);
  }

  /// Shows the confirmation number for a few seconds, then continues on to
  /// the dashboard by itself (the person can also tap through immediately).
  void _startAutoContinue() {
    const seconds = 4;
    setState(() => _autoContinueSeconds = seconds);
    _autoContinueTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _autoContinueSeconds -= 1);
      if (_autoContinueSeconds <= 0) {
        timer.cancel();
        _goToDashboard();
      }
    });
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final masked = await _auth.requestPasswordResetCode(email);
      if (!mounted) return;
      setState(() {
        _email = email;
        _maskedEmail = masked;
        _step = _Step.code;
      });
      _startCooldown(60);
    } on ApiException catch (e) {
      final retry = e.body?['retryAfterSeconds'];
      setState(() => _error = e.message);
      if (retry is int) _startCooldown(retry);
    } catch (e) {
      setState(() => _error = 'Could not send the code: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await _auth.verifyPasswordResetCode(_email, code);
      if (!mounted) return;
      setState(() {
        _resetToken = token;
        _step = _Step.newPassword;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not verify the code: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setNewPassword() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = "Passwords don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final confirmation = await _auth.resetPasswordWithCode(_resetToken, password);
      if (!mounted) return;
      setState(() {
        _confirmationNumber = confirmation;
        _step = _Step.done;
      });
      _startAutoContinue();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not reset the password: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _step == _Step.done ? null : AppBar(title: const Text('Forgot Password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: switch (_step) {
              _Step.email => _emailStep(),
              _Step.code => _codeStep(),
              _Step.newPassword => _newPasswordStep(),
              _Step.done => _doneStep(),
            },
          ),
        ),
      ),
    );
  }

  Widget _errorText() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(_error!, style: const TextStyle(color: Colors.red)),
    );
  }

  Widget _emailStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_reset, size: 48),
        const SizedBox(height: 16),
        const Text(
          'Enter the email address on your account and we\'ll send you a 6-digit verification code.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.email_outlined)),
          onSubmitted: (_) => _sendCode(),
        ),
        _errorText(),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _busy ? null : _sendCode,
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Send code'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Back to login')),
      ],
    );
  }

  Widget _codeStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 48),
        const SizedBox(height: 16),
        Text('Enter the 6-digit code sent to $_maskedEmail.', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofocus: true,
          maxLength: 6,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: const InputDecoration(counterText: '', hintText: '••••••'),
          onSubmitted: (_) => _verifyCode(),
        ),
        _errorText(),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _verifyCode,
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Verify code'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: (_busy || _resendCooldown > 0) ? null : _sendCode,
          child: Text(_resendCooldown > 0 ? 'Resend code in ${_resendCooldown}s' : 'Resend code'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _step = _Step.email;
                    _error = null;
                  }),
          child: const Text('Use a different email'),
        ),
      ],
    );
  }

  Widget _newPasswordStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.password, size: 48),
        const SizedBox(height: 16),
        const Text('Choose a new password.', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(
          controller: _passwordController,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New password', prefixIcon: Icon(Icons.lock_outline)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.lock_outline)),
          onSubmitted: (_) => _setNewPassword(),
        ),
        _errorText(),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _setNewPassword,
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Reset password'),
        ),
      ],
    );
  }

  Widget _doneStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 56),
        const SizedBox(height: 16),
        const Text('Password reset', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Your password has been changed.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              const Text('Confirmation number', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              SelectableText(_confirmationNumber, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _goToDashboard,
          child: Text(_autoContinueSeconds > 0 ? 'Continue to dashboard (${_autoContinueSeconds}s)' : 'Continue to dashboard'),
        ),
      ],
    );
  }
}