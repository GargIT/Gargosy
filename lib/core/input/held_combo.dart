import 'dart:async';

import 'gamepad_service.dart';

/// The buttons a quit combo is made of (#141) held on one controller, told
/// by [GamepadService] whether or not Gargosy's window has focus: a new
/// [HeldButtons] each time that controller's set changes.
final heldButtons = StreamController<HeldButtons>.broadcast();

/// Every button a quit combo can use. The stick clicks (#163) aren't
/// [GameAction]s: Gargosy's menus don't use them.
enum PadButton {
  select,
  start,
  l1,
  r1,
  l3,
  r3;

  /// The button a mapped [action] is, if a combo can use it.
  static PadButton? ofAction(GameAction action) => switch (action) {
    GameAction.select => select,
    GameAction.start => start,
    GameAction.l1 => l1,
    GameAction.r1 => r1,
    _ => null,
  };

  /// GameInput's name for a stick click, the same on every controller.
  static PadButton? ofKey(String key) => switch (key.toLowerCase()) {
    'leftthumbstick' => l3,
    'rightthumbstick' => r3,
    _ => null,
  };
}

/// The [PadButton]s that [pad] holds now.
class HeldButtons {
  const HeldButtons(this.pad, this.buttons);
  final String pad;
  final Set<PadButton> buttons;
}

/// Tracks the [PadButton]s held per controller; [update] gives that
/// controller's held set when it changes.
class HeldCombo {
  final _held = <String, Set<PadButton>>{};

  /// [button] went [down] (or up) on [pad]; what [pad] holds when that
  /// changed, else null.
  HeldButtons? update(String pad, PadButton button, {required bool down}) {
    final held = _held.putIfAbsent(pad, () => {});
    final changed = down ? held.add(button) : held.remove(button);
    return changed ? HeldButtons(pad, Set.unmodifiable(held)) : null;
  }
}
