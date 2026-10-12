import '../core/storage/app_preferences.dart';

/// Whether an emulator starts in full screen, per profile (the play screen's
/// switch), and how each emulator is told so on its command line.
class Fullscreen {
  Fullscreen._();

  static String _key(String emulatorId) => 'fullscreen.$emulatorId';

  /// On unless the profile turned it off for [emulatorId].
  static bool isOn(AppPreferences prefs, String emulatorId) => prefs.getBool(_key(emulatorId)) ?? true;

  static Future<void> set(AppPreferences prefs, String emulatorId, bool on) => prefs.setBool(_key(emulatorId), on);

  /// The arguments for on and off. RetroArch has no "windowed" flag; off is
  /// written into its config instead ([ProfileLaunchConfig]).
  static const Map<String, ({List<String> on, List<String> off})> _flags = {
    'retroarch': (on: ['--fullscreen'], off: []),
    'dolphin': (on: ['-C', 'Dolphin.Display.Fullscreen=True'], off: ['-C', 'Dolphin.Display.Fullscreen=False']),
    'pcsx2': (on: ['-fullscreen'], off: ['-nofullscreen']),
    'duckstation': (on: ['-fullscreen'], off: ['-nofullscreen']),
    'ppsspp': (on: ['--fullscreen'], off: ['--windowed']),
    'mame': (on: ['-nowindow'], off: ['-window']),
    'xenia_canary': (on: ['--fullscreen=true'], off: ['--fullscreen=false']),
    'xemu': (on: ['-full-screen'], off: []),
    'flycast': (on: ['-config', 'window:fullscreen=yes'], off: ['-config', 'window:fullscreen=no']),
    'mgba': (on: ['-f'], off: []),
    'ares': (on: ['--fullscreen'], off: []),
    // RPCS3's --fullscreen works only with --no-gui, which also ends RPCS3
    // with the game (issue #10).
    'rpcs3': (on: ['--no-gui', '--fullscreen'], off: ['--no-gui']),
  };

  static bool supports(String emulatorId) => _flags.containsKey(emulatorId);

  /// [args] (everything before the ROM) with the flag for [on] in front: a
  /// strategy's last argument may take the ROM next (Dolphin's `-e`). The
  /// strategies' own `-fullscreen` (PCSX2, DuckStation) is taken out first,
  /// so it can't outvote off.
  static List<String> apply(String emulatorId, bool on, List<String> args) {
    final flags = _flags[emulatorId];
    if (flags == null) return args;
    final own = flags.on;
    final rest = own.length == 1 ? args.where((a) => a != own.single).toList() : args;
    return [...(on ? flags.on : flags.off), ...rest];
  }
}
