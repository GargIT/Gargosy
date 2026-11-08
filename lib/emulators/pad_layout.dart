import '../core/storage/app_preferences.dart';
import '../core/storage/ini_file.dart';
import '../l10n/tr.dart';
import 'config_files.dart';

/// One controller layout for every emulator (#246): player 1's buttons
/// written into the emulator's own input settings in the profile at launch,
/// so a new profile's controller works at its first game. The first
/// controller, by position: the bottom face button is the emulated pad's
/// bottom one (Standard), or the bottom and right ones and the left and top
/// ones swapped (Nintendo-style). docs/emulator-profiles.md lists who uses it.
enum PadLayout {
  /// Standard, written only where player 1 has no controller mapped (a new
  /// profile, an emulator never set up); a mapping made by hand stays.
  fillIn('Standard where nothing is set up'),

  /// Standard at every launch.
  standard('Standard'),

  /// Nintendo-style at every launch: A/B and X/Y swapped.
  nintendo('Nintendo-style (A/B and X/Y swapped)'),

  /// Nothing written: each emulator's own settings (what was written
  /// before stays).
  own("Each emulator's own");

  const PadLayout(this._label);
  final String _label;
  String get label => tr(_label);

  /// The profile's choice (`prefs.json`, so it moves with the profile).
  static const prefKey = 'controller.layout';

  static PadLayout read(AppPreferences prefs) =>
      values.where((l) => l.name == prefs.getString(prefKey)).firstOrNull ?? PadLayout.fillIn;

  static Future<void> write(AppPreferences prefs, PadLayout layout) => prefs.setString(prefKey, layout.name);

  /// The emulators that write it; any other keeps its own settings.
  static const usedBy = {'retroarch', 'pcsx2', 'duckstation', 'dolphin'};

  /// The layout written now for an emulator whose player 1 [mapped] (has a
  /// controller binding) or not: null when nothing is written.
  PadLayout? writes({required bool mapped}) => switch (this) {
    fillIn => mapped ? null : standard,
    own => null,
    _ => this,
  };
}

/// The emulators that write it, by name, as Settings says them.
const padLayoutEmulators = 'RetroArch, PCSX2, DuckStation, Dolphin (GameCube)';

/// A face button by where it sits on the pad.
enum _Face { south, east, west, north }

_Face _swap(_Face f, PadLayout l) => l != PadLayout.nintendo
    ? f
    : switch (f) {
        _Face.south => _Face.east,
        _Face.east => _Face.south,
        _Face.west => _Face.north,
        _Face.north => _Face.west,
      };

final _controllerBinding = RegExp(r'^\s*(SDL|XInput|DInput|DInput8|Evdev)-\d', caseSensitive: false);

/// Writes [values] of [layout] into [section] of [ini]: player 1 counts as
/// mapped when [mapped] says so, unless it holds exactly what Gargosy writes
/// for Standard or Nintendo-style (Gargosy's own, so going back to the
/// default puts Standard back). Whether it wrote.
bool _apply(
  IniFile ini,
  String section,
  PadLayout layout,
  Map<String, String> Function(PadLayout) values, {
  required bool mapped,
}) {
  final ours = [
    PadLayout.standard,
    PadLayout.nintendo,
  ].any((l) => values(l).entries.every((e) => ini.get(section, e.key) == e.value));
  final l = layout.writes(mapped: mapped && !ours);
  if (l == null) return false;
  for (final MapEntry(:key, :value) in values(l).entries) {
    ini.set(section, key, value);
  }
  return true;
}

// ── A PlayStation pad: PCSX2's and DuckStation's [Pad1], as their own ──
// ── automatic mapping writes it; only the face buttons' names differ.  ──

const _psFace = {'Cross': _Face.south, 'Circle': _Face.east, 'Square': _Face.west, 'Triangle': _Face.north};
const _psRest = {
  'Up': 'DPadUp',
  'Right': 'DPadRight',
  'Down': 'DPadDown',
  'Left': 'DPadLeft',
  'Select': 'Back',
  'Start': 'Start',
  'L1': 'LeftShoulder',
  'L2': '+LeftTrigger',
  'R1': 'RightShoulder',
  'R2': '+RightTrigger',
  'L3': 'LeftStick',
  'R3': 'RightStick',
  'Analog': 'Guide',
  'LUp': '-LeftY',
  'LRight': '+LeftX',
  'LDown': '+LeftY',
  'LLeft': '-LeftX',
  'RUp': '-RightY',
  'RRight': '+RightX',
  'RDown': '+RightY',
  'RLeft': '-RightX',
  'LargeMotor': 'LargeMotor',
  'SmallMotor': 'SmallMotor',
};

Map<String, String> _psPad(PadLayout l, Map<_Face, String> faceName) => {
  for (final MapEntry(:key, :value) in _psFace.entries) key: 'SDL-0/${faceName[_swap(value, l)]}',
  for (final MapEntry(:key, :value) in _psRest.entries) key: 'SDL-0/$value',
};

bool _psMapped(IniFile ini) => [..._psFace.keys, ..._psRest.keys].any((k) {
  final binding = ini.get('Pad1', k);
  return binding != null && _controllerBinding.hasMatch(binding);
});

const _pcsx2FaceName = {
  _Face.south: 'FaceSouth',
  _Face.east: 'FaceEast',
  _Face.west: 'FaceWest',
  _Face.north: 'FaceNorth',
};

/// PCSX2's player 1 in [ini] (`PCSX2.ini`) by [layout]; whether it wrote.
/// Mapped is a controller on any of its buttons (PCSX2's own defaults are
/// the keyboard's).
bool applyPcsx2Layout(IniFile ini, PadLayout layout) {
  final wrote = _apply(ini, 'Pad1', layout, (l) => _psPad(l, _pcsx2FaceName), mapped: _psMapped(ini));
  if (wrote && ini.get('Pad1', 'Type') == null) ini.set('Pad1', 'Type', 'DualShock2');
  return wrote;
}

const _sdlFaceName = {_Face.south: 'A', _Face.east: 'B', _Face.west: 'X', _Face.north: 'Y'};

/// DuckStation's player 1 in [ini] (`settings.ini`) by [layout]; whether it
/// wrote. The pad's type stays DuckStation's.
bool applyDuckstationLayout(IniFile ini, PadLayout layout) =>
    _apply(ini, 'Pad1', layout, (l) => _psPad(l, _sdlFaceName), mapped: _psMapped(ini));

// ── Dolphin: Config\GCPadNew.ini [GCPad1] on the first XInput pad ──

/// The first Xbox-type controller in Dolphin, whatever its name.
const dolphinPadDevice = 'XInput/0/Gamepad';

const _dolphinFace = {
  'Buttons/A': _Face.south,
  'Buttons/B': _Face.east,
  'Buttons/X': _Face.west,
  'Buttons/Y': _Face.north,
};
const _xinputFaceName = {
  _Face.south: '`Button A`',
  _Face.east: '`Button B`',
  _Face.west: '`Button X`',
  _Face.north: '`Button Y`',
};
const _dolphinRest = {
  'Buttons/Z': '`Shoulder R`',
  'Buttons/Start': '`Start`',
  'Main Stick/Up': '`Left Y+`',
  'Main Stick/Down': '`Left Y-`',
  'Main Stick/Left': '`Left X-`',
  'Main Stick/Right': '`Left X+`',
  'C-Stick/Up': '`Right Y+`',
  'C-Stick/Down': '`Right Y-`',
  'C-Stick/Left': '`Right X-`',
  'C-Stick/Right': '`Right X+`',
  'Triggers/L': '`Trigger L`',
  'Triggers/R': '`Trigger R`',
  'Triggers/L-Analog': '`Trigger L`',
  'Triggers/R-Analog': '`Trigger R`',
  'D-Pad/Up': '`Pad N`',
  'D-Pad/Down': '`Pad S`',
  'D-Pad/Left': '`Pad W`',
  'D-Pad/Right': '`Pad E`',
  'Rumble/Motor': '`Motor L` | `Motor R`',
};

Map<String, String> _dolphinPad(PadLayout l) => {
  'Device': dolphinPadDevice,
  for (final MapEntry(:key, :value) in _dolphinFace.entries) key: _xinputFaceName[_swap(value, l)]!,
  ..._dolphinRest,
};

/// Dolphin's GameCube player 1 in [ini] (`GCPadNew.ini`) by [layout];
/// whether it wrote. Mapped is a controller as its device (Dolphin's
/// default is the keyboard). Only an Xbox-type pad is written; another
/// pad is mapped in Dolphin once, and then stays. Wii remotes keep
/// Dolphin's own settings.
bool applyDolphinLayout(IniFile ini, PadLayout layout) {
  final device = ini.get('GCPad1', 'Device') ?? '';
  return _apply(
    ini,
    'GCPad1',
    layout,
    _dolphinPad,
    mapped: device.isNotEmpty && !device.toLowerCase().contains('keyboard'),
  );
}

// ── RetroArch: its controller profiles (autoconfig) map every known pad ──

/// RetroPad's face buttons in RetroArch's cfg, and SDL's number for the
/// button at each position (SDL numbers every pad it knows A, B, X, Y as
/// 0–3; XInput's driver doesn't for a pad that isn't XInput).
const _retroArchFace = {
  'input_player1_b_btn': _Face.south,
  'input_player1_a_btn': _Face.east,
  'input_player1_y_btn': _Face.west,
  'input_player1_x_btn': _Face.north,
};
const _padButtonNumber = {_Face.south: '0', _Face.east: '1', _Face.west: '2', _Face.north: '3'};

final _retroArchKey = RegExp(r'^\s*(input_player1_[abxy]_btn)\s*=\s*"([^"]*)"', multiLine: true);

/// RetroArch's player 1 in [text] (`retroarch.cfg`) by [layout]. Its own
/// controller profiles already map a new profile's pad (Standard), so only
/// the face buttons are written over them: swapped for Nintendo-style, on
/// SDL's driver (the same numbers for every pad), and put back to the
/// profiles' (`nul`) for Standard, or by the default when Gargosy's
/// swap is there. Null when nothing changes.
String? applyRetroArchLayout(String text, PadLayout layout) {
  final now = {for (final m in _retroArchKey.allMatches(text)) m.group(1)!: m.group(2)!};
  final swapped = _retroArchFace.entries.every(
    (e) => now[e.key] == _padButtonNumber[_swap(e.value, PadLayout.nintendo)],
  );
  final write = switch (layout) {
    PadLayout.nintendo => PadLayout.nintendo,
    PadLayout.standard => PadLayout.standard,
    PadLayout.fillIn when swapped => PadLayout.standard,
    _ => null,
  };
  if (write == null) return null;
  return setRetroArchKeys(text, {
    if (write == PadLayout.nintendo) 'input_joypad_driver': 'sdl2',
    for (final MapEntry(:key, :value) in _retroArchFace.entries)
      key: write == PadLayout.standard ? 'nul' : _padButtonNumber[_swap(value, write)]!,
  });
}
