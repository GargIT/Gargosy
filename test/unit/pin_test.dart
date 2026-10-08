import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/pin.dart';

void main() {
  PinHash make(String pin) => PinHash.create(pin, random: Random(1), iterations: 1000);

  test('only four digits are a PIN', () {
    expect(PinHash.isValidPin('1234'), isTrue);
    for (final bad in ['123', '12345', 'abcd', '12 4', '']) {
      expect(PinHash.isValidPin(bad), isFalse, reason: bad);
      expect(() => PinHash.create(bad), throwsArgumentError);
    }
  });

  test('the right PIN verifies, a wrong one does not, and the PIN is not stored', () {
    final h = make('4711');
    expect(h.verify('4711'), isTrue);
    expect(h.verify('4712'), isFalse);
    expect(h.toJson().toString(), isNot(contains('4711')));
  });

  test('round-trips through JSON', () {
    final h = make('0000');
    expect(PinHash.fromJson(h.toJson()).verify('0000'), isTrue);
  });

  test('two hashes of the same PIN differ (random salt)', () {
    expect(PinHash.create('1111', iterations: 1000).hash, isNot(PinHash.create('1111', iterations: 1000).hash));
  });

  test('five wrong tries lock for 30 seconds, then the right PIN works', () async {
    var now = DateTime(2026, 10, 8, 12);
    final gate = PinGate(make('1234'), now: () => now);
    for (var i = 0; i < 4; i++) {
      expect(await gate.attempt('0000'), PinResult.wrong);
    }
    expect(await gate.attempt('0000'), PinResult.locked);
    expect(gate.lockedFor, const Duration(seconds: 30));
    expect(await gate.attempt('1234'), PinResult.locked);
    now = now.add(const Duration(seconds: 31));
    expect(gate.lockedFor, isNull);
    expect(await gate.attempt('1234'), PinResult.ok);
  });

  test('a right PIN resets the count of wrong tries', () async {
    final gate = PinGate(make('1234'));
    for (var i = 0; i < 4; i++) {
      await gate.attempt('0000');
    }
    expect(await gate.attempt('1234'), PinResult.ok);
    expect(await gate.attempt('0000'), PinResult.wrong);
  });
}
