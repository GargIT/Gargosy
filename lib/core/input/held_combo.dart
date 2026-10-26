import 'dart:async';

import 'gamepad_service.dart';

/// The buttons a quit combo is made of (#141) held on one controller, told
/// by [GamepadService] whether or not Gargosy's window has focus: a new
/// [HeldButtons] each time that controller's set changes.
final heldButtons = StreamController<HeldButtons>.broadcast();

/// What [GamepadService] watches: every button a quit combo can use.
const quitComboButtons = {GameAction.select, GameAction.start, GameAction.l1, GameAction.r1};

/// The [buttons] of [quitComboButtons] that [pad] holds now.
class HeldButtons {
  const HeldButtons(this.pad, this.buttons);
  final String pad;
  final Set<GameAction> buttons;
}

/// Tracks [buttons] held per controller; [update] gives that controller's
/// held set when it changes.
class HeldCombo {
  HeldCombo(this.buttons);

  final Set<GameAction> buttons;
  final _held = <String, Set<GameAction>>{};

  /// [action] went [down] (or up) on [pad]; what [pad] holds when that
  /// changed, else null.
  HeldButtons? update(String pad, GameAction action, {required bool down}) {
    if (!buttons.contains(action)) return null;
    final held = _held.putIfAbsent(pad, () => {});
    final changed = down ? held.add(action) : held.remove(action);
    return changed ? HeldButtons(pad, Set.unmodifiable(held)) : null;
  }
}
