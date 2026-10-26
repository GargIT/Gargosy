import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/held_combo.dart';
import 'package:gargosy/core/storage/app_preferences.dart';
import 'package:gargosy/play/quit_combo.dart';

import '../helpers/profile_test_env.dart';

void main() {
  test("each controller's held buttons, told when they change", () {
    final combo = HeldCombo();
    expect(combo.update('p1', PadButton.select, down: true)?.buttons, {PadButton.select});
    expect(combo.update('p2', PadButton.l1, down: true)?.buttons, {PadButton.l1}, reason: 'its own set');
    expect(combo.update('p1', PadButton.l1, down: true)?.buttons, {PadButton.select, PadButton.l1});
    expect(combo.update('p1', PadButton.select, down: false)?.buttons, {PadButton.l1});
    expect(combo.update('p1', PadButton.select, down: false), isNull, reason: 'no change');
  });

  test("a combo can use the stick clicks, from a mapped action or GameInput's own name", () {
    expect(PadButton.ofAction(GameAction.l1), PadButton.l1);
    expect(PadButton.ofAction(GameAction.confirm), isNull, reason: 'not part of any combo');
    expect(PadButton.ofKey('leftThumbstick'), PadButton.l3);
    expect(PadButton.ofKey('rightThumbstick'), PadButton.r3);
    expect(PadButton.ofKey('a'), isNull);
    expect(QuitButtons.sticks.buttons, {PadButton.l3, PadButton.r3});
  });

  test('QuitCombo fires once when one controller holds all its buttons for the hold time', () {
    fakeAsync((async) {
      final held = StreamController<HeldButtons>.broadcast();
      var quits = 0;
      final combo = QuitCombo(held.stream, QuitButtons.selectBumpers.buttons, () async => quits++);
      held.add(const HeldButtons('p1', {PadButton.select, PadButton.l1}));
      held.add(const HeldButtons('p2', {PadButton.r1}));
      async.elapse(const Duration(seconds: 2));
      expect(quits, 0, reason: 'split over two controllers');
      held.add(const HeldButtons('p1', {PadButton.select, PadButton.l1, PadButton.r1, PadButton.start}));
      async.elapse(const Duration(milliseconds: 900));
      expect(quits, 0);
      async.elapse(const Duration(milliseconds: 200));
      expect(quits, 1);
      held.add(const HeldButtons('p1', {}));
      held.add(const HeldButtons('p1', {PadButton.select, PadButton.l1, PadButton.r1}));
      async.elapse(const Duration(seconds: 2));
      expect(quits, 1, reason: 'once');
      combo.cancel();
    });
  });

  test("the choice: Select + LB + RB by default, the old switch's off kept, off and back", () async {
    AppPreferences prefs = MemoryPrefs();
    expect(QuitButtons.of(prefs), QuitButtons.selectBumpers);
    await prefs.setBool(QuitButtons.oldPrefKey, false);
    expect(QuitButtons.of(prefs), isNull);
    await prefs.setString(QuitButtons.prefKey, QuitButtons.selectStart.name);
    expect(QuitButtons.of(prefs), QuitButtons.selectStart);
    await prefs.setString(QuitButtons.prefKey, QuitButtons.off);
    expect(QuitButtons.of(prefs), isNull);
    prefs = MemoryPrefs();
    await prefs.setString(QuitButtons.prefKey, 'gone');
    expect(QuitButtons.of(prefs), QuitButtons.selectBumpers);
  });
}
