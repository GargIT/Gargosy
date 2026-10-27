import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/input/gamepad_service.dart';
import '../input/gargosy_intents.dart';
import '../theme/tokens.dart';
import 'g_focusable.dart';
import 'hint_bar.dart';
import '../../l10n/tr.dart';

/// Four-digit PIN entry for the controller (spec §5).
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.title, required this.onComplete, required this.onCancel, this.error});

  final String title;

  /// Returns an error to show (the digits clear), or null when accepted.
  final Future<String?> Function(String pin) onComplete;
  final VoidCallback onCancel;
  final String? error;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _digits = '';
  late String? _error = widget.error;
  bool _busy = false;

  Future<void> _press(String d) async {
    if (_busy || _digits.length >= 4) return;
    setState(() {
      _digits += d;
      _error = null;
    });
    if (_digits.length == 4) {
      setState(() => _busy = true);
      final error = await widget.onComplete(_digits);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _digits = '';
        _error = error;
      });
    }
  }

  void _back() {
    if (_digits.isEmpty) {
      widget.onCancel();
    } else {
      setState(() => _digits = _digits.substring(0, _digits.length - 1));
    }
  }

  static final _digitKeys = {
    for (var i = 0; i <= 9; i++) ...{
      LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i): '$i',
      LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + i): '$i',
    },
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final digit = _digitKeys[event.logicalKey];
    if (digit != null) {
      _press(digit);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _back();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _key(String label, VoidCallback onPress, {bool autofocus = false}) => Padding(
    padding: const EdgeInsets.all(GSpace.s2),
    child: GFocusable(
      autofocus: autofocus,
      borderRadius: GRadius.pill,
      onActivate: onPress,
      child: Container(
        width: 76,
        height: 76,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: GColors.surface, shape: BoxShape.circle),
        child: Text(
          label,
          style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {BackIntent: CallbackAction<BackIntent>(onInvoke: (_) => _back())},
      child: Focus(
        onKeyEvent: _onKey,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: GSpace.s5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      key: ValueKey('pin-dot-$i'),
                      margin: const EdgeInsets.all(GSpace.s2),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _digits.length ? GColors.primary : null,
                        border: Border.all(color: GColors.borderStrong, width: 2),
                      ),
                      child: SizedBox.expand(key: Key(i < _digits.length ? 'pin-dot-filled' : 'pin-dot-empty')),
                    ),
                ],
              ),
              SizedBox(
                height: 28,
                child: _error == null
                    ? null
                    : Text(
                        _error!,
                        style: const TextStyle(color: GColors.danger, fontSize: GFont.lg),
                      ),
              ),
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final d in row) _key(d, () => _press(d), autofocus: d == '1')],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _key('⌫', _back),
                  _key('0', () => _press('0')),
                  const SizedBox(width: 76 + GSpace.s4),
                ],
              ),
              HintBar(hints: [Hint(GameAction.confirm, tr('Press')), Hint(GameAction.back, tr('Delete / Back'))]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [PinPad] until [check] accepts a PIN (returns null); returns that PIN,
/// or null when cancelled.
Future<String?> showPinEntry(
  BuildContext context, {
  required String title,
  required Future<String?> Function(String pin) check,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: GColors.bg.withValues(alpha: 0.92),
    builder: (dialogContext) => Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: PinPad(
        title: title,
        onComplete: (pin) async {
          final error = await check(pin);
          if (error == null && dialogContext.mounted) Navigator.of(dialogContext).pop(pin);
          return error;
        },
        onCancel: () => Navigator.of(dialogContext).pop(),
      ),
    ),
  );
}
