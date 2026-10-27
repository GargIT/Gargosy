import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../storage/app_preferences.dart';
import 'held_combo.dart';

/// Which HID button (counted from 0, as SDL's `b<n>`) is which [PadButton],
/// per USB vendor and product id, from SDL's `gamecontrollerdb.txt` (its
/// Windows lines).
class SdlButtons {
  SdlButtons._(this._byDevice);

  final Map<(int, int), Map<int, PadButton>> _byDevice;

  static const _names = {
    'back': PadButton.select,
    'start': PadButton.start,
    'leftshoulder': PadButton.l1,
    'rightshoulder': PadButton.r1,
    'leftstick': PadButton.l3,
    'rightstick': PadButton.r3,
  };

  static SdlButtons parse(String database) {
    final byDevice = <(int, int), Map<int, PadButton>>{};
    for (final line in database.split('\n')) {
      if (!line.contains('platform:Windows')) continue;
      final parts = line.split(',');
      final device = deviceOf(parts.first.trim());
      if (device == null || byDevice.containsKey(device)) continue;
      final buttons = <int, PadButton>{};
      for (final part in parts.skip(2)) {
        final pair = part.split(':');
        if (pair.length != 2) continue;
        final button = _names[pair[0].trim()];
        final ref = pair[1].trim();
        final index = ref.startsWith('b') ? int.tryParse(ref.substring(1)) : null;
        if (button != null && index != null) buttons[index] = button;
      }
      if (buttons.isNotEmpty) byDevice[device] = buttons;
    }
    return SdlButtons._(byDevice);
  }

  /// The vendor and product id in an SDL GUID (`03000000` + vendor, little
  /// endian + `0000` + product + …).
  @visibleForTesting
  static (int, int)? deviceOf(String guid) {
    if (guid.length != 32) return null;
    final vendor = int.tryParse(guid.substring(10, 12) + guid.substring(8, 10), radix: 16);
    final product = int.tryParse(guid.substring(18, 20) + guid.substring(16, 18), radix: 16);
    return vendor == null || product == null ? null : (vendor, product);
  }

  /// [vendor]'s [product]'s buttons; null when SDL doesn't know it.
  Map<int, PadButton>? of(int vendor, int product) => _byDevice[(vendor, product)];
}

/// Where a controller's [HidButtonMap] came from (#171).
enum HidButtonSource {
  /// The player pressed each button in Settings → Controller.
  learned('taught'),

  /// SDL's controller database.
  sdl("SDL's list"),

  /// [guessedHidButtons]: neither knows the controller.
  guess('a guess');

  const HidButtonSource(this.label);
  final String label;
}

/// A controller's buttons and where they came from.
typedef HidButtonMap = ({Map<int, PadButton> buttons, HidButtonSource source});

/// The usual order of a gamepad's HID buttons (A, B, X, Y, LB, RB, Select,
/// Start, L3, R3), for a controller neither taught nor in SDL's list.
const guessedHidButtons = {
  4: PadButton.l1,
  5: PadButton.r1,
  6: PadButton.select,
  7: PadButton.start,
  8: PadButton.l3,
  9: PadButton.r3,
};

/// `vvvv:pppp` in hex, as the log and [LearnedHidButtons] write it.
String hidDeviceKey(int vendor, int product) =>
    '${vendor.toRadixString(16).padLeft(4, '0')}:${product.toRadixString(16).padLeft(4, '0')}';

/// A controller's buttons: taught first, then SDL's list (unless
/// [sdl] is null: `--hid-ignore-sdl`), then [guessedHidButtons].
HidButtonMap hidButtonsFor(
  int vendor,
  int product, {
  required SdlButtons? sdl,
  required Map<String, Map<int, PadButton>> learned,
}) {
  final taught = learned[hidDeviceKey(vendor, product)];
  if (taught != null && taught.isNotEmpty) return (buttons: taught, source: HidButtonSource.learned);
  final known = sdl?.of(vendor, product);
  if (known != null) return (buttons: known, source: HidButtonSource.sdl);
  return (buttons: guessedHidButtons, source: HidButtonSource.guess);
}

/// The buttons taught in Settings → Controller (#171), per controller
/// ([hidDeviceKey]), in the app-wide pref [prefKey] as JSON:
/// `{"2dc8:6006": {"select": 10, "l1": 6, …}}`.
abstract final class LearnedHidButtons {
  static const prefKey = 'controller.hidButtons';

  static Map<String, Map<int, PadButton>> read(AppPreferences prefs) {
    final raw = prefs.getString(prefKey);
    if (raw == null) return const {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const {};
      final all = <String, Map<int, PadButton>>{};
      for (final key in json.keys) {
        final value = json[key];
        if (value is! Map<String, dynamic>) continue;
        final buttons = all[key] = {};
        for (final button in PadButton.values) {
          final index = value[button.name];
          if (index is int) buttons[index] = button;
        }
      }
      return all;
    } on FormatException {
      return const {};
    }
  }

  /// Keeps [buttons] for the controller [key], in place of what it had.
  static Future<void> save(AppPreferences prefs, String key, Map<int, PadButton> buttons) {
    final all = {...read(prefs), key: buttons};
    return prefs.setString(prefKey, _encode(all));
  }

  /// Forgets every taught controller.
  static Future<void> forgetAll(AppPreferences prefs) => prefs.remove(prefKey);

  static String _encode(Map<String, Map<int, PadButton>> all) => jsonEncode({
    for (final key in all.keys) key: {for (final index in all[key]!.keys) all[key]![index]!.name: index},
  });
}
