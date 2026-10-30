import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profiles/pin.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_providers.dart';
import 'pin_pad.dart';
import '../../l10n/tr.dart';

/// Asks for [profile]'s PIN through its [PinGate] (5 tries, then 30 s, the
/// same count wherever it's asked: the picker, the PIN card, the age limit).
/// True when it was right, or the profile has no PIN.
Future<bool> checkProfilePin(BuildContext context, WidgetRef ref, Profile profile, {String? title}) async {
  final pin = profile.pin;
  if (pin == null) return true;
  final gate = ref.read(pinGatesProvider).putIfAbsent(profile.id, () => PinGate(pin));
  final ok = await showPinEntry(
    context,
    title: title ?? tr('PIN for {0}', [profile.name]),
    check: (entered) async {
      switch (await gate.attempt(entered)) {
        case PinResult.ok:
          return null;
        case PinResult.wrong:
          return tr('Wrong PIN');
        case PinResult.locked:
          return tr('Too many tries. Wait {0} seconds.', [gate.lockedFor?.inSeconds ?? 30]);
      }
    },
  );
  return ok != null;
}
