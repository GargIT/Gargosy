import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/held_combo.dart';

void main() {
  test('Select + Start on one controller is held; on two controllers it is not', () {
    final combo = HeldCombo({GameAction.select, GameAction.start});
    expect(combo.update('p1', GameAction.select, down: true), isNull);
    expect(combo.update('p2', GameAction.start, down: true), isNull, reason: 'another controller');
    expect(combo.update('p1', GameAction.start, down: true), isTrue);
    expect(combo.update('p1', GameAction.confirm, down: true), isNull, reason: 'not part of it');
    expect(combo.update('p1', GameAction.select, down: false), isFalse);
    expect(combo.update('p1', GameAction.select, down: false), isNull, reason: 'no change');
    expect(combo.on, isFalse);
  });
}
