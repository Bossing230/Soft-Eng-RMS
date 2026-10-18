import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rms/Frontend/services/api_services.dart';
import 'package:rms/Frontend/services/auth_services.dart';

import '../../core/routes/app_router.dart';

enum _Step { confirm, code, newPassword, done }

/// The forgot-password flow, reached either from the persistent "Forgot
/// password?" link on the login screen, or from the 3-wrong-passwords
/// lockout dialog. The email address is never typed by the person — only
/// ever the one already on the account — so this can't be used to redirect
/// a reset to an address an attacker controls.
class ForgotPasswordPage extends StatefulWidget {
  final String username;
  const ForgotPasswordPage({super.key, required this.username});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _auth = AuthService();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _Step _step = _Step.confirm;
  bool _busy = false;
  String? _error;
  String _maskedEmail = '';
  String _resetToken = '';
  String _confirmationNumber = '';
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _cooldownTimer?.cancel();
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

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final masked = await _auth.requestPasswordResetCode(widget.username);
      if (!mounted) return;
      setState(() {
        _maskedEmail = masked;
        _step = _Step.code;
      });
      _startCooldown(60);
    } on ApiException catch (e) {
      final retry = e.body?['retryAfterSeconds'];
      setState(() => _error = retry != null ? '${e.message}' : e.message);
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
      final token = await _auth.verifyPasswordResetCode(widget.username, code);
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
      appBar: _step == _Step.done ? null : AppBar(title: const Text('Reset Password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: switch (_step) {
              _Step.confirm => _confirmStep(),
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

  Widget _confirmStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_reset, size: 48),
        const SizedBox(height: 16),
        Text(
          "We'll send a 6-digit verification code to the email address on file for ${widget.username}.",
          textAlign: TextAlign.center,
        ),
        _errorText(),
        const SizedBox(height: 24),
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
          onPressed: () => AppRouter.goToRoleDashboard(context),
          child: const Text('Continue to dashboard'),
        ),
      ],
    );
  }
}