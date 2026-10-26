import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/input/held_combo.dart';
import '../core/input/xinput_pads.dart';
import '../core/platform/platform_info.dart';
import '../core/storage/app_preferences.dart';
import '../profiles/profile_providers.dart';

/// The buttons held to quit a game (#141), this PC's choice in Settings →
/// Controller. Select + Start alone is often taken (Game Bar, Steam, an
/// emulator's menu), so the default adds the bumpers instead of Start.
enum QuitButtons {
  selectBumpers('Select + LB + RB', {PadButton.select, PadButton.l1, PadButton.r1}),
  startBumpers('Start + LB + RB', {PadButton.start, PadButton.l1, PadButton.r1}),
  selectStartBumpers('Select + Start + LB + RB', {PadButton.select, PadButton.start, PadButton.l1, PadButton.r1}),
  selectStart('Select + Start', {PadButton.select, PadButton.start}),

  /// Both sticks pressed in (#163): no emulator menu or Game Bar uses them.
  sticks('Both sticks in (L3 + R3)', {PadButton.l3, PadButton.r3});

  const QuitButtons(this.label, this.buttons);
  final String label;
  final Set<PadButton> buttons;

  static const fallback = QuitButtons.selectBumpers;

  /// The pref's value: a [QuitButtons] name, or `off`.
  static const prefKey = 'controller.quitButtons';
  static const off = 'off';

  /// The on/off switch before the choice: off stays off.
  static const oldPrefKey = 'controller.quitCombo';

  /// This PC's choice; null when quitting with the controller is off.
  static QuitButtons? of(AppPreferences prefs) {
    final v = prefs.getString(prefKey);
    if (v == null) return prefs.getBool(oldPrefKey) == false ? null : fallback;
    if (v == off) return null;
    return QuitButtons.values.where((b) => b.name == v).firstOrNull ?? fallback;
  }

  static String labelOf(QuitButtons? b) => b?.label ?? 'Off';
}

/// Quitting a game with the controller (#141): [buttons] held together for
/// [hold] on one controller calls [onQuit], once. Listens to [held]
/// (`heldButtons`) until [cancel].
class QuitCombo {
  QuitCombo(Stream<HeldButtons> held, this.buttons, this.onQuit, {this.hold = holdTime}) {
    _sub = held.listen((h) {
      final was = _on;
      _pads[h.pad] = h.buttons.containsAll(buttons);
      final on = _on;
      if (on == was) return;
      debugPrint('[Quit] ${on ? 'held' : 'let go'}');
      _timer?.cancel();
      _timer = on && !_fired ? Timer(hold, _fire) : null;
    });
  }

  static const holdTime = Duration(seconds: 1);

  final Set<PadButton> buttons;
  final Future<void> Function() onQuit;
  final Duration hold;
  late final StreamSubscription<HeldButtons> _sub;
  final _pads = <String, bool>{};
  Timer? _timer;
  bool _fired = false;

  bool get _on => _pads.values.any((on) => on);

  void _fire() {
    debugPrint('[Quit] held ${hold.inMilliseconds} ms: closing the game');
    _fired = true;
    unawaited(onQuit());
  }

  void cancel() {
    _timer?.cancel();
    _sub.cancel();
  }
}

/// The buttons that quit a game on this PC, null when off; read again
/// after Settings changes it.
final quitButtonsProvider = Provider<QuitButtons?>((ref) => QuitButtons.of(ref.watch(appPreferencesProvider)));

/// XInput read while a game runs (#141); null off Windows.
final xinputPadsProvider = Provider<XInputPads?>(
  (ref) => PlatformInfo.current.isWindows ? XInputPads(heldButtons) : null,
);
