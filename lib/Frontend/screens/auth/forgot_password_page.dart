import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rms/Frontend/services/api_services.dart';
import 'package:rms/Frontend/services/auth_services.dart';

import '../../core/routes/app_router.dart';
import '../../core/theme/app_theme.dart';

enum _Step { email, code, newPassword, done }

const _codeLength = 6; // matches the backend's 6-digit code (authController.js)
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Forgot-password flow: email -> 6-digit code -> new password -> dashboard.
///
/// The code is always sent to the account's own email on file. The address
/// typed here is only used to look the account up.
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

  /// Bumped whenever the code boxes should clear themselves (new code sent,
  /// or a wrong one was rejected).
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

  // ---------------------------------------------------------------- timers

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
        if (_resendCooldown <= 0) {
          _resendCooldown = 0;
          timer.cancel();
        }
      });
    });
  }

  void _goToDashboard() {
    _autoContinueTimer?.cancel();
    if (mounted) AppRouter.goToRoleDashboard(context);
  }

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

  // --------------------------------------------------------------- actions

  String _friendly(Object e) {
    if (e is TimeoutException) {
      return 'The server is taking too long to respond. Please try again.';
    }
    return 'Could not reach the server. Check your connection and try again.';
  }

  Future<void> _sendCode() async {
    if (_busy) return;
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
        // An earlier code is still valid: go enter it and respect the cooldown.
        setState(() {
          _email = email;
          _maskedEmail = maskedFromCooldown;
          _step = _Step.code;
          _code = '';
          _error = null;
          _codeBoxesGeneration++;
        });
        _startCooldown(retry);
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_busy) return;
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
        _codeBoxesGeneration++; // clear the boxes so a wrong code isn't re-sent by accident
      });
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setNewPassword() async {
    if (_busy) return;
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
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------- UI

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
    final content = switch (_step) {
      _Step.email => _emailStep(),
      _Step.code => _codeStep(),
      _Step.newPassword => _newPasswordStep(),
      _Step.done => _doneStep(),
    };

    return Scaffold(
      appBar: _step == _Step.done ? null : AppBar(title: Text(_appBarTitle())),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_step != _Step.done) ...[
                  _stepper(),
                  const SizedBox(height: 16),
                ],
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: KeyedSubtree(key: ValueKey(_step), child: content),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepper() {
    final current = switch (_step) {
      _Step.email => 0,
      _Step.code => 1,
      _ => 2,
    };
    const labels = ['Email', 'Verify', 'New password'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < labels.length - 1 ? 8 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= current ? AppTheme.primary : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == current ? FontWeight.w700 : FontWeight.w400,
                      color: i <= current ? Colors.black87 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _errorText() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buttonChild(String label, String busyLabel) {
    if (!_busy) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        const SizedBox(width: 10),
        Text(busyLabel),
      ],
    );
  }

  ButtonStyle get _linkStyle => ButtonStyle(
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        backgroundColor: WidgetStateProperty.all(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
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

  Widget _emailStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_reset, size: 44, color: AppTheme.primary),
        const SizedBox(height: 14),
        const Text(
          "Enter the email address on your account and we'll send you a 6-digit verification code.",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.send,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Email address',
            prefixIcon: const Icon(Icons.email_outlined),
            fillColor: AppTheme.background,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.black12)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
          ),
          onSubmitted: (_) => _sendCode(),
        ),
        _errorText(),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _busy ? null : _sendCode,
          child: _buttonChild('Send code', 'Sending...'),
        ),
        const SizedBox(height: 4),
        TextButton(
          style: _linkStyle,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Back to login'),
        ),
      ],
    );
  }

  Widget _codeStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Check your email', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            text: 'Enter the 6-digit code sent to ',
            children: [TextSpan(text: _maskedEmail, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87))],
          ),
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 24),
        Center(
          child: _OtpBoxes(
            key: ValueKey(_codeBoxesGeneration),
            length: _codeLength,
            enabled: !_busy,
            hasError: _error != null,
            onChanged: (value) => setState(() {
              _code = value;
              if (_error != null) _error = null;
            }),
            onCompleted: (value) {
              setState(() => _code = value);
              _verifyCode();
            },
          ),
        ),
        _errorText(),
        const SizedBox(height: 14),
        Center(
          child: _resendCooldown > 0
              ? Text('Resend code in ${_fmt(_resendCooldown)}', style: const TextStyle(color: Colors.black45, fontSize: 13))
              : TextButton(
                  style: _linkStyle,
                  onPressed: _busy ? null : _sendCode,
                  child: const Text("Didn't get it? Resend code"),
                ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: (_busy || _code.length != _codeLength) ? null : _verifyCode,
          child: _buttonChild('Continue', 'Checking...'),
        ),
        const SizedBox(height: 4),
        TextButton(
          style: _linkStyle,
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

  // 0..4 strength score for the meter.
  int _strength(String p) {
    var s = 0;
    if (p.length >= 6) s++;
    if (p.length >= 10) s++;
    if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'\d').hasMatch(p)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
    return s.clamp(0, 4);
  }

  Widget _strengthMeter() {
    final p = _passwordController.text;
    if (p.isEmpty) return const SizedBox.shrink();
    final s = _strength(p);
    const labels = ['Too weak', 'Weak', 'Fair', 'Good', 'Strong'];
    final colors = [Colors.red, Colors.deepOrange, Colors.amber[800]!, Colors.lightGreen[700]!, Colors.green[700]!];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: (s + 1) / 5, minHeight: 5, backgroundColor: Colors.black12, color: colors[s]),
            ),
          ),
          const SizedBox(width: 10),
          Text(labels[s], style: TextStyle(fontSize: 12, color: colors[s], fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _newPasswordStep() {
    final mismatch = _confirmController.text.isNotEmpty && _confirmController.text != _passwordController.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Create a new password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Use at least 6 characters. A longer password with mixed characters is stronger.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 24),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'New password',
            prefixIcon: const Icon(Icons.lock_outline),
            fillColor: AppTheme.background,
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        _strengthMeter(),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmController,
          obscureText: _obscureConfirm,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Confirm new password',
            prefixIcon: const Icon(Icons.lock_outline),
            fillColor: AppTheme.background,
            errorText: mismatch ? "Passwords don't match" : null,
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          onSubmitted: (_) => _setNewPassword(),
        ),
        _errorText(),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _busy ? null : _setNewPassword,
          child: _buttonChild('Save password', 'Saving...'),
        ),
      ],
    );
  }

  Widget _doneStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 400),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: const Icon(Icons.check_circle, color: Colors.green, size: 60),
        ),
        const SizedBox(height: 16),
        const Text('Password changed', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text("You're signed in with your new password.", textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              const Text('Confirmation number', style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 4),
              SelectableText(_confirmationNumber, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _goToDashboard,
          child: Text(_autoContinueSeconds > 0 ? 'Go to dashboard (${_autoContinueSeconds}s)' : 'Go to dashboard'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Segmented digit-code input: one box per digit, auto-advancing, paste-aware.
//
// BUG FIX: the old version wrapped each TextField in a KeyboardListener that
// used the SAME FocusNode as the TextField. That nests a node inside itself,
// which creates a loop in Flutter's focus tree and freezes the page
// ("Page Unresponsive"). Backspace handling now lives on the node itself
// (FocusNode.onKeyEvent), so there is exactly one Focus widget per node.
// ---------------------------------------------------------------------------

class _OtpBoxes extends StatefulWidget {
  final int length;
  final bool enabled;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;
  const _OtpBoxes({
    super.key,
    required this.length,
    required this.enabled,
    required this.hasError,
    required this.onChanged,
    required this.onCompleted,
  });

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  late final List<TextEditingController> _controllers = List.generate(widget.length, (_) => TextEditingController());
  late final List<FocusNode> _focusNodes = List.generate(
    widget.length,
    (i) => FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
          _onBackspace(i);
        }
        return KeyEventResult.ignored;
      },
    ),
  );

  @override
  void initState() {
    super.initState();
    // Select the digit when a box gets focus so typing replaces it.
    for (var i = 0; i < widget.length; i++) {
      _focusNodes[i].addListener(() {
        if (_focusNodes[i].hasFocus) {
          final c = _controllers[i];
          c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
        }
      });
    }
  }

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
    if (value.length > 1) {
      // Paste or autofill dropped several digits into one box: spread them out.
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

  OutlineInputBorder _border(Color color, double width) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: width));

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 54,
            child: TextField(
              controller: _controllers[i],
              focusNode: _focusNodes[i],
              enabled: widget.enabled,
              autofocus: i == 0,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length), // lets a full code be pasted into one box
              ],
              decoration: InputDecoration(
                counterText: '',
                contentPadding: EdgeInsets.zero,
                filled: true,
                fillColor: AppTheme.background,
                enabledBorder: _border(widget.hasError ? errorColor : Colors.black26, 1.2),
                disabledBorder: _border(Colors.black12, 1.2),
                focusedBorder: _border(widget.hasError ? errorColor : AppTheme.primary, 2),
              ),
              onChanged: (v) => _onChanged(i, v),
            ),
          ),
        ],
      ],
    );
  }
}