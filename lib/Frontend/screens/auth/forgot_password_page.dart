import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rms/Frontend/services/api_services.dart';
import 'package:rms/Frontend/services/auth_services.dart';

import '../../core/routes/app_router.dart';

enum _Step { email, code, newPassword, done }

const _codeLength = 6; // matches the backend's 6-digit code — see authController.js
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
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  String? _error;
  String _email = '';
  String _maskedEmail = '';
  String _code = '';
  String _resetToken = '';
  String _confirmationNumber = '';
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  Timer? _autoContinueTimer;
  int _autoContinueSeconds = 0;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  /// Bumped every time the code boxes should clear themselves (a fresh
  /// code was sent, or a wrong one was just rejected).
  int _codeBoxesGeneration = 0;

  @override
  void dispose() {
    _emailController.dispose();
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
        _code = '';
        _codeBoxesGeneration++;
      });
      _startCooldown(60);
    } on ApiException catch (e) {
      final retry = e.body?['retryAfterSeconds'];
      final maskedFromCooldown = e.body?['maskedEmail'] as String?;
      if (retry is int && maskedFromCooldown != null) {
        // A code from an earlier request is still valid — move on to
        // entering it instead of leaving the person stuck here with no way
        // forward. Resend just respects the remaining cooldown.
        setState(() {
          _email = email;
          _maskedEmail = maskedFromCooldown;
          _step = _Step.code;
          _code = '';
          _codeBoxesGeneration++;
        });
        _startCooldown(retry);
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = 'Could not send the code: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_code.length != _codeLength) {
      setState(() => _error = 'Enter all $_codeLength digits from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await _auth.verifyPasswordResetCode(_email, _code);
      if (!mounted) return;
      setState(() {
        _resetToken = token;
        _step = _Step.newPassword;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _code = '';
        _codeBoxesGeneration++; // clear the boxes so a wrong code isn't just re-submitted by accident
      });
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

  String _appBarTitle() {
    switch (_step) {
      case _Step.email:
      case _Step.code:
        return 'Forgot your password';
      case _Step.newPassword:
        return 'Create a new password';
      case _Step.done:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _step == _Step.done ? null : AppBar(title: Text(_appBarTitle())),
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
      child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
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
    final canResend = !_busy && _resendCooldown <= 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Forgot your password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Enter the verification code sent to your email\n$_maskedEmail', style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        Center(
          child: _OtpBoxes(
            key: ValueKey(_codeBoxesGeneration),
            length: _codeLength,
            enabled: !_busy,
            onChanged: (value) => setState(() => _code = value),
            onCompleted: (value) {
              setState(() => _code = value);
              _verifyCode();
            },
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: canResend
              ? TextButton(onPressed: _sendCode, child: const Text('Resend code'))
              : Text(
                  "Didn't receive the code? 00:${_resendCooldown.toString().padLeft(2, '0')}",
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
        ),
        _errorText(),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: (_busy || _code.length != _codeLength) ? null : _verifyCode,
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Continue'),
        ),
        const SizedBox(height: 8),
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
        const Text('Create a new password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Enter a new password and try not to forget it.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 24),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'New password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: 'Re-enter the new password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          onSubmitted: (_) => _setNewPassword(),
        ),
        _errorText(),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _setNewPassword,
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Continue'),
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

// ---------------------------------------------------------------------------
// Segmented digit-code input: one box per digit, auto-advancing, matching
// the "enter the code" design.
// ---------------------------------------------------------------------------

class _OtpBoxes extends StatefulWidget {
  final int length;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;
  const _OtpBoxes({super.key, required this.length, required this.enabled, required this.onChanged, required this.onCompleted});

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  late final List<TextEditingController> _controllers = List.generate(widget.length, (_) => TextEditingController());
  late final List<FocusNode> _focusNodes = List.generate(widget.length, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _onChanged(int index, String value) {
    // Paste or autofill may drop more than one character into a single box.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < widget.length; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final lastFilled = (digits.length - 1).clamp(0, widget.length - 1);
      _focusNodes[lastFilled].requestFocus();
    } else if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    widget.onChanged(_value);
    if (_value.length == widget.length) {
      widget.onCompleted(_value);
    }
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      widget.onChanged(_value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 54,
            child: KeyboardListener(
              // Shares the TextField's own focus node below, rather than
              // creating a new one here: a fresh FocusNode on every rebuild
              // would leak (never disposed) and would never actually be
              // focused, since the TextField focuses `_focusNodes[i]` instead
              // — so it wouldn't see the key presses it's meant to catch.
              focusNode: _focusNodes[i],
              onKeyEvent: (event) {
                if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
                  _onBackspace(i);
                }
              },
              child: TextField(
                controller: _controllers[i],
                focusNode: _focusNodes[i],
                enabled: widget.enabled,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.zero),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) => _onChanged(i, v),
              ),
            ),
          ),
        ],
      ],
    );
  }
}