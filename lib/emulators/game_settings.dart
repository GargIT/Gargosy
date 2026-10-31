import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/storage/app_preferences.dart';
import '../core/storage/ini_file.dart';
import '../profiles/path_guard.dart';

/// The emulator's widescreen switch for one game: left as the emulator has
/// it, or on or off for this game only.
enum Widescreen { emulator, on, off }

/// #234: what the play screen sets for one game in one emulator, per
/// profile: extra command-line arguments, RetroArch's shader (a preset
/// under RetroArch's `shaders\`, relative to it), the widescreen switch.
class GameSettings {
  const GameSettings({this.args = '', this.shader, this.widescreen = Widescreen.emulator});

  final String args;
  final String? shader;
  final Widescreen widescreen;

  static const none = GameSettings();

  bool get isEmpty => args.trim().isEmpty && shader == null && widescreen == Widescreen.emulator;

  GameSettings copyWith({String? args, String? Function()? shader, Widescreen? widescreen}) => GameSettings(
    args: args ?? this.args,
    shader: shader == null ? this.shader : shader(),
    widescreen: widescreen ?? this.widescreen,
  );

  Map<String, Object?> toJson() => {
    if (args.trim().isNotEmpty) 'args': args,
    'shader': ?shader,
    if (widescreen != Widescreen.emulator) 'widescreen': widescreen.name,
  };

  static GameSettings fromJson(Object? json) {
    if (json is! Map) return none;
    final shader = json['shader'];
    return GameSettings(
      args: json['args'] is String ? json['args'] as String : '',
      // Only a path inside RetroArch's shaders folder.
      shader:
          shader is String &&
              shader.isNotEmpty &&
              !p.isAbsolute(shader) &&
              !shader.split(RegExp(r'[\\/]')).contains('..')
          ? shader
          : null,
      widescreen: Widescreen.values.where((w) => w.name == json['widescreen']).firstOrNull ?? Widescreen.emulator,
    );
  }
}

/// The profile's game settings, in its `prefs.json` under
/// `game.settings.<rom id>`: one entry per emulator.
class GameSettingsStore {
  GameSettingsStore(this._prefs);

  final AppPreferences _prefs;

  static String key(String gameId) => 'game.settings.$gameId';

  Map<String, Object?> _all(String gameId) {
    final raw = _prefs.getString(key(gameId));
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw);
      return json is Map ? Map<String, Object?>.from(json) : {};
    } on FormatException {
      return {};
    }
  }

  GameSettings read(String gameId, String emulatorId) => GameSettings.fromJson(_all(gameId)[emulatorId]);

  Future<void> write(String gameId, String emulatorId, GameSettings s) async {
    final all = _all(gameId);
    if (s.isEmpty) {
      all.remove(emulatorId);
    } else {
      all[emulatorId] = s.toJson();
    }
    if (all.isEmpty) {
      await _prefs.remove(key(gameId));
    } else {
      await _prefs.setString(key(gameId), jsonEncode(all));
    }
  }

  /// Every emulator's settings for [gameId] gone.
  Future<void> reset(String gameId) => _prefs.remove(key(gameId));
}

/// The emulators whose own widescreen switch Gargosy sets per game.
const widescreenEmulators = {'pcsx2', 'dolphin', 'duckstation', 'flycast'};

/// [text] as command-line arguments: split at spaces, a "quoted part" kept
/// whole, quotes taken off.
List<String> splitArgs(String text) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  var any = false;
  for (final ch in text.split('')) {
    if (ch == '"') {
      quoted = !quoted;
      any = true;
    } else if (!quoted && (ch == ' ' || ch == '\t')) {
      if (any) out.add('$cur');
      cur.clear();
      any = false;
    } else {
      cur.write(ch);
      any = true;
    }
  }
  if (any) out.add('$cur');
  return out;
}

/// RetroArch's shader folder beside its exe.
String retroArchShaderDir(String exeDir) => p.join(exeDir, 'shaders');

/// The shader presets RetroArch has (`.slangp`, `.glslp`, `.cgp`), relative
/// to [shaderDir], sorted; none when it has no folder.
List<String> retroArchShaders(String shaderDir) {
  final dir = io.Directory(shaderDir);
  if (!dir.existsSync()) return const [];
  return [
    for (final e in dir.listSync(recursive: true, followLinks: false))
      if (e is io.File && const {'.slangp', '.glslp', '.cgp'}.contains(p.extension(e.path).toLowerCase()))
        p.relative(e.path, from: shaderDir),
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// The arguments [s] adds for [emulatorId], before the game's: RetroArch's
/// `--set-shader`, Dolphin's and Flycast's widescreen for this launch only,
/// then the player's own.
List<String> gameSettingArgs(String emulatorId, GameSettings s, String exeDir) {
  final on = s.widescreen == Widescreen.on;
  final shader = emulatorId == 'retroarch' ? s.shader : null;
  return [
    if (shader != null) ...['--set-shader', p.join(retroArchShaderDir(exeDir), shader)],
    if (s.widescreen != Widescreen.emulator)
      ...switch (emulatorId) {
        // GFX.ini [Settings] wideScreenHack, for this launch only.
        'dolphin' => ['-C', 'GFX.Settings.wideScreenHack=${on ? 'True' : 'False'}'],
        'flycast' => ['-config', 'config:rend.WideScreen=${on ? 'yes' : 'no'}'],
        _ => const <String>[],
      },
    ...splitArgs(s.args),
  ];
}

/// The keys a game's widescreen sets in an emulator's own settings file
/// (PCSX2, DuckStation: neither takes it on the command line).
Map<(String, String), String>? _widescreenKeys(String emulatorId, bool on) => switch (emulatorId) {
  'pcsx2' => {('EmuCore', 'EnableWideScreenPatches'): '$on'},
  'duckstation' => {('GPU', 'WidescreenHack'): '$on', ('Display', 'AspectRatio'): on ? '16:9' : '4:3'},
  _ => null,
};

/// Where the emulator's settings file is while it runs (after the launch
/// config's `prepare`): PCSX2's in the profile, DuckStation's swapped in
/// beside its exe.
String? _settingsFile(String emulatorId, String data, String exeDir) => switch (emulatorId) {
  'pcsx2' => p.join(data, 'PCSX2', 'inis', 'PCSX2.ini'),
  'duckstation' => p.join(exeDir, 'settings.ini'),
  _ => null,
};

/// Sets the game's widescreen in PCSX2's or DuckStation's own settings for
/// this game, run after the launch config's `prepare`. The value the player
/// had before is kept in `<data>\.gargosy-game-settings.json` and put back
/// at the next launch of a game that leaves widescreen to the emulator.
void applyGameSettingKeys(String emulatorId, GameSettings s, String data, String exeDir, PathGuard guard) {
  final path = _settingsFile(emulatorId, data, exeDir);
  final keys = _widescreenKeys(emulatorId, s.widescreen == Widescreen.on);
  if (path == null || keys == null) return;
  final marker = io.File(guard.check(p.join(data, '.gargosy-game-settings.json')));
  Map<String, Object?> kept = {};
  if (marker.existsSync()) {
    try {
      kept = Map<String, Object?>.from(jsonDecode(marker.readAsStringSync()) as Map);
    } on Object {
      kept = {};
    }
  }
  final file = io.File(guard.check(path));
  if (!file.existsSync() && s.widescreen == Widescreen.emulator) return;
  final ini = IniFile(file.existsSync() ? file.readAsStringSync() : '');
  if (s.widescreen == Widescreen.emulator) {
    if (kept.isEmpty) return;
    for (final k in keys.keys) {
      final name = '${k.$1}.${k.$2}';
      if (!kept.containsKey(name)) continue;
      final was = kept[name];
      if (was is String) {
        ini.set(k.$1, k.$2, was);
      } else {
        ini.remove(k.$1, k.$2);
      }
    }
    file.writeAsStringSync(ini.toText());
    marker.deleteSync();
    return;
  }
  for (final e in keys.entries) {
    final name = '${e.key.$1}.${e.key.$2}';
    if (!kept.containsKey(name)) kept[name] = ini.get(e.key.$1, e.key.$2);
    ini.set(e.key.$1, e.key.$2, e.value);
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(ini.toText());
  marker.parent.createSync(recursive: true);
  marker.writeAsStringSync(jsonEncode(kept));
}

/// RetroArch's shader folder under its install [installDir]
/// (`emulators\retroarch\`): beside the exe, which may sit one folder down;
/// null when there's none.
String? findRetroArchShaderDir(String installDir) {
  final here = retroArchShaderDir(installDir);
  if (io.Directory(here).existsSync()) return here;
  final dir = io.Directory(installDir);
  if (!dir.existsSync()) return null;
  for (final e in dir.listSync(followLinks: false)) {
    if (e is io.Directory && io.Directory(retroArchShaderDir(e.path)).existsSync()) return retroArchShaderDir(e.path);
  }
  return null;
}
