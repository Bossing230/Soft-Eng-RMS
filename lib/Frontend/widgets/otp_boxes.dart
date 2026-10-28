import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rms/Frontend/core/theme/app_theme.dart';

/// Segmented digit-code input: one box per digit, auto-advancing, paste-aware.
/// Shared by the forgot-password page and the new-employee email check.
///
/// Backspace handling lives on each FocusNode (FocusNode.onKeyEvent). Never
/// wrap a TextField in a KeyboardListener that reuses the same FocusNode: it
/// nests the node inside itself and freezes the page.
///
/// Do not use a LayoutBuilder in [build]. This widget is shown inside an
/// AlertDialog (the new-employee dialog), and AlertDialog measures its content
/// with IntrinsicWidth. LayoutBuilder cannot answer that measurement, so in a
/// debug build (flutter run) it throws, the dialog turns blank, and the app
/// ends on the red "'_owner != null'" screen. Release builds (the website) skip
/// that check, which is why it only showed up on the phone.
class OtpBoxes extends StatefulWidget {
  final int length;
  final bool enabled;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;
  const OtpBoxes({
    super.key,
    this.length = 6,
    required this.enabled,
    required this.hasError,
    required this.onChanged,
    required this.onCompleted,
  });

  @override
  State<OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<OtpBoxes> {
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
    const gap = 8.0;
    const boxWidth = 44.0;

    // Fixed-size boxes inside a FittedBox: on a narrow dialog the whole row
    // scales down to fit, so six boxes always fit, and (unlike LayoutBuilder)
    // it can be measured by the dialog's IntrinsicWidth.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.length; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            SizedBox(
              width: boxWidth,
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
      ),
    );
  }
}