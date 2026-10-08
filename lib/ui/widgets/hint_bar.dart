import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/gamepad_service.dart';
import '../../providers/ui_provider.dart';
import '../theme/tokens.dart';

class Hint {
  const Hint(this.action, this.label);
  final GameAction action;
  final String label;
}

/// Button hints along the bottom, for the controller (A, B, X, Y …) and the
/// keyboard (Enter, Esc …). Hidden for the mouse (spec §7).
class HintBar extends ConsumerWidget {
  const HintBar({super.key, required this.hints});

  final List<Hint> hints;

  static const _pad = {
    GameAction.confirm: 'A', GameAction.back: 'B', GameAction.detail: 'X', GameAction.favorite: 'Y',
    GameAction.l1: 'LB', GameAction.r1: 'RB', GameAction.start: 'Start', GameAction.confirmHold: 'Hold A',
  };
  static const _keys = {
    GameAction.confirm: 'Enter', GameAction.back: 'Esc', GameAction.detail: 'Right-click', GameAction.favorite: 'F',
    GameAction.l1: 'PgUp', GameAction.r1: 'PgDn', GameAction.start: 'Menu', GameAction.confirmHold: 'Hold Enter',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(inputModeProvider);
    if (mode == InputMode.mouse) return const SizedBox.shrink();
    final names = mode == InputMode.gamepad ? _pad : _keys;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: GSpace.rowPad, vertical: GSpace.s3),
      child: Wrap(
        spacing: GSpace.s6,
        children: [
          for (final h in hints)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: GSpace.s2, vertical: 2),
                decoration: BoxDecoration(color: GColors.surfaceHover, borderRadius: BorderRadius.circular(GRadius.chip)),
                child: Text(names[h.action] ?? h.action.name, style: const TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: GSpace.s2),
              Text(h.label, style: const TextStyle(fontSize: GFont.md, color: GColors.fgSecondary)),
            ]),
        ],
      ),
    );
  }
}
