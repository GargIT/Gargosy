import 'package:flutter/material.dart';

import '../../core/input/gamepad_service.dart';
import '../theme/tokens.dart';
import 'g_focusable.dart';
import 'hint_bar.dart';

Widget _dialogButton(String label, VoidCallback onPress, {bool autofocus = false, bool primary = false, Color? color}) =>
    GFocusable(
      autofocus: autofocus,
      borderRadius: GRadius.pill,
      onActivate: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
        decoration: BoxDecoration(
            color: primary ? GColors.primary : GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      ),
    );

Widget _panel({required String title, required List<Widget> children, double width = 480}) => Center(
      child: Material(
        color: GColors.panel,
        borderRadius: BorderRadius.circular(GRadius.lg),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.all(GSpace.s5),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700)),
              const SizedBox(height: GSpace.s3),
              ...children,
            ]),
          ),
        ),
      ),
    );

/// A yes/no question for the controller: A on the focused button, B is
/// [no]. [focusYes] false puts focus on [no] (for a question whose yes
/// replaces something).
Future<bool> showConfirm(BuildContext context,
    {required String title, required String body, required String yes, String no = 'Cancel', bool focusYes = true, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => _panel(title: title, children: [
      Text(body, style: const TextStyle(color: GColors.fgSecondary)),
      const SizedBox(height: GSpace.s5),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        _dialogButton(no, () => Navigator.of(c).pop(false), autofocus: !focusYes),
        const SizedBox(width: GSpace.s2),
        _dialogButton(yes, () => Navigator.of(c).pop(true),
            autofocus: focusYes, primary: !danger, color: danger ? GColors.danger : null),
      ]),
      const SizedBox(height: GSpace.s3),
      const HintBar(hints: [Hint(GameAction.confirm, 'Select'), Hint(GameAction.back, 'Cancel')]),
    ]),
  );
  return ok == true;
}

/// Pick one of [labels]; null when closed with B. [current] has focus.
Future<int?> showChoice(BuildContext context, {required String title, required List<String> labels, int? current}) =>
    showDialog<int>(
      context: context,
      builder: (c) => _panel(title: title, width: 420, children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < labels.length; i++)
                GFocusable(
                  autofocus: i == (current ?? 0),
                  borderRadius: GRadius.md,
                  onActivate: () => Navigator.of(c).pop(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
                    child: Row(children: [
                      Expanded(child: Text(labels[i], style: const TextStyle(fontSize: GFont.lg))),
                      if (i == current) const Icon(Icons.check, color: GColors.primary),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: GSpace.s3),
        const HintBar(hints: [Hint(GameAction.confirm, 'Select'), Hint(GameAction.back, 'Cancel')]),
      ]),
    );
