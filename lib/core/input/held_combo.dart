import 'dart:async';

import 'gamepad_service.dart';

/// Whether some controller holds Select and Start together (#141), told by
/// [GamepadService] whether or not Gargosy's window has focus: true when
/// both go down on one controller, false when either comes up.
final selectStartHeld = StreamController<bool>.broadcast();

/// Tracks [buttons] held per controller; [update] says when "all of them
/// on one controller" changes.
class HeldCombo {
  HeldCombo(this.buttons);

  final Set<GameAction> buttons;
  final _held = <String, Set<GameAction>>{};
  bool _on = false;

  bool get on => _on;

  /// [action] went [down] (or up) on [pad]; the new state when it changed,
  /// else null.
  bool? update(String pad, GameAction action, {required bool down}) {
    if (!buttons.contains(action)) return null;
    final held = _held.putIfAbsent(pad, () => {});
    down ? held.add(action) : held.remove(action);
    final now = _held.values.any((h) => h.length == buttons.length);
    if (now == _on) return null;
    _on = now;
    return now;
  }
}
