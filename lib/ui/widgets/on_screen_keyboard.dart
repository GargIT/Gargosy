import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/input/gamepad_service.dart';
import '../input/gargosy_intents.dart';
import '../theme/tokens.dart';
import 'g_focusable.dart';
import 'hint_bar.dart';

/// Text entry with the controller (spec §7): a key grid laid out for URLs,
/// names and passwords. A physical keyboard types straight in.
class OnScreenKeyboard extends StatefulWidget {
  const OnScreenKeyboard({
    super.key,
    required this.title,
    this.initial = '',
    this.obscure = false,
    required this.onDone,
    required this.onCancel,
  });

  final String title;
  final String initial;
  final bool obscure;
  final ValueChanged<String> onDone;
  final VoidCallback onCancel;

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  late String _text = widget.initial;
  bool _shift = false;

  static const _rows = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', '@'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', '.', '-', '_'],
    ['/', ':', '!', '?', '#', '&', '=', '+', '%', '~'],
  ];

  void _type(String s) => setState(() => _text += s);

  void _backspace() {
    if (_text.isEmpty) {
      widget.onCancel();
    } else {
      setState(() => _text = _text.substring(0, _text.length - 1));
    }
  }

  void _done() => widget.onDone(_text);

  String _label(String k) => _shift ? k.toUpperCase() : k;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _done();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 0x20 && ch.codeUnitAt(0) != 0x7F) {
      _type(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _key(String label, VoidCallback onPress, {bool autofocus = false, int flex = 1}) => Expanded(
    flex: flex,
    child: Padding(
      padding: const EdgeInsets.all(GSpace.s1),
      child: GFocusable(
        autofocus: autofocus,
        borderRadius: GRadius.md,
        onActivate: onPress,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.md)),
          child: Text(
            label,
            style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final shown = widget.obscure ? '•' * _text.length : _text;
    return Actions(
      actions: {
        BackIntent: CallbackAction<BackIntent>(onInvoke: (_) => _backspace()),
        DetailIntent: CallbackAction<DetailIntent>(onInvoke: (_) => _type(' ')),
        MenuIntent: CallbackAction<MenuIntent>(onInvoke: (_) => _done()),
      },
      // Catches a physical keyboard's keys as they bubble up from the focused
      // key; never a D-pad target itself (it covers every row, so down would
      // land on it and stay there).
      child: Focus(
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: GSpace.s3),
                Container(
                  padding: const EdgeInsets.all(GSpace.s4),
                  decoration: BoxDecoration(
                    color: GColors.bgElevated,
                    borderRadius: BorderRadius.circular(GRadius.lg),
                    border: Border.all(color: GColors.borderStrong),
                  ),
                  child: Text(shown.isEmpty ? ' ' : shown, style: const TextStyle(fontSize: GFont.xxl)),
                ),
                const SizedBox(height: GSpace.s4),
                for (var r = 0; r < _rows.length; r++)
                  Row(
                    children: [
                      for (var c = 0; c < _rows[r].length; c++)
                        _key(_label(_rows[r][c]), () => _type(_label(_rows[r][c])), autofocus: r == 0 && c == 0),
                    ],
                  ),
                Row(
                  children: [
                    _key('⇧', () => setState(() => _shift = !_shift)),
                    _key('Space', () => _type(' '), flex: 4),
                    _key('⌫', _backspace, flex: 2),
                    _key('Done', _done, flex: 3),
                  ],
                ),
                const HintBar(
                  hints: [
                    Hint(GameAction.confirm, 'Press'),
                    Hint(GameAction.back, 'Delete'),
                    Hint(GameAction.detail, 'Space'),
                    Hint(GameAction.start, 'Done'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [OnScreenKeyboard] as a full-screen dialog; null when cancelled.
Future<String?> showOnScreenKeyboard(
  BuildContext context, {
  required String title,
  String initial = '',
  bool obscure = false,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: GColors.bg.withValues(alpha: 0.92),
    builder: (dialogContext) => Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: OnScreenKeyboard(
        title: title,
        initial: initial,
        obscure: obscure,
        onDone: (v) => Navigator.of(dialogContext).pop(v),
        onCancel: () => Navigator.of(dialogContext).pop(),
      ),
    ),
  );
}
