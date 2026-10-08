import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'pbkdf2.dart';

/// A profile's PIN as a salted PBKDF2 hash. A family lock, not security:
/// anyone on the same Windows account can open the folder (spec §5).
class PinHash {
  const PinHash({required this.salt, required this.hash, required this.iterations});

  final String salt; // base64
  final String hash; // base64
  final int iterations;

  static const defaultIterations = 60000;

  static bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  factory PinHash.create(String pin, {Random? random, int iterations = defaultIterations}) {
    if (!isValidPin(pin)) throw ArgumentError.value('****', 'pin', 'must be four digits');
    final r = random ?? Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));
    return PinHash(
      salt: base64Encode(salt),
      hash: base64Encode(pbkdf2Sha256(utf8.encode(pin), salt, iterations, 32)),
      iterations: iterations,
    );
  }

  bool verify(String pin) {
    if (!isValidPin(pin)) return false;
    final actual = pbkdf2Sha256(utf8.encode(pin), base64Decode(salt), iterations, 32);
    final expected = base64Decode(hash);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// [verify] off the UI thread (60 000 rounds take a moment).
  Future<bool> verifyAsync(String pin) {
    final copy = PinHash(salt: salt, hash: hash, iterations: iterations);
    return Isolate.run(() => copy.verify(pin));
  }

  Map<String, dynamic> toJson() => {'salt': salt, 'hash': hash, 'iterations': iterations};

  factory PinHash.fromJson(Map<String, dynamic> json) => PinHash(
        salt: json['salt'] as String,
        hash: json['hash'] as String,
        iterations: json['iterations'] as int,
      );
}

enum PinResult { ok, wrong, locked }

/// Tries against one profile's PIN: after [maxTries] wrong tries in a row,
/// every try is refused for [lockout].
class PinGate {
  PinGate(this.pin, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final PinHash pin;
  final DateTime Function() _now;
  static const maxTries = 5;
  static const lockout = Duration(seconds: 30);

  int _failures = 0;
  DateTime? _lockedUntil;

  /// How long tries are still refused, or null when they aren't.
  Duration? get lockedFor {
    final until = _lockedUntil;
    if (until == null) return null;
    final left = until.difference(_now());
    if (left <= Duration.zero) {
      _lockedUntil = null;
      return null;
    }
    return left;
  }

  Future<PinResult> attempt(String entered) async {
    if (lockedFor != null) return PinResult.locked;
    if (await pin.verifyAsync(entered)) {
      _failures = 0;
      return PinResult.ok;
    }
    _failures++;
    if (_failures >= maxTries) {
      _failures = 0;
      _lockedUntil = _now().add(lockout);
      return PinResult.locked;
    }
    return PinResult.wrong;
  }
}
