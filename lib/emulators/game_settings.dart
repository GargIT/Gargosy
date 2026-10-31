import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:flutter/foundation.dart';
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

/// What Gargosy sets per game in one emulator (#234), in one place: its
/// widescreen (by argument for this launch, or by keys in the settings file
/// it reads while it runs), whether it takes a shader, and the arguments
/// that point it at the profile or name its game, which extra arguments may
/// never repeat.
class GameSettingsSupport {
  const GameSettingsSupport({
    this.widescreenArgs,
    this.widescreenKeys,
    this.settingsFile,
    this.shaders = false,
    this.reserved = const {},
  });

  final List<String> Function(bool on)? widescreenArgs;
  final Map<(String, String), String> Function(bool on)? widescreenKeys;

  /// Where the settings file is while the emulator runs (after the launch
  /// config's `prepare`), from the profile's data folder and the exe's.
  final String Function(String data, String exeDir)? settingsFile;
  final bool shaders;

  /// Lower case; a `--name=value` form counts too.
  final Set<String> reserved;

  bool get widescreen => widescreenArgs != null || widescreenKeys != null;

  static const none = GameSettingsSupport();

  static final _table = <String, GameSettingsSupport>{
    'retroarch': const GameSettingsSupport(
      shaders: true,
      reserved: {'-c', '--config', '--appendconfig', '-l', '--libretro', '-s', '--save', '--savestate'},
    ),
    // GFX.ini [Settings] wideScreenHack, for this launch only.
    'dolphin': GameSettingsSupport(
      widescreenArgs: (on) => ['-C', 'GFX.Settings.wideScreenHack=${on ? 'True' : 'False'}'],
      reserved: const {'-u', '--user', '-e', '--exec', '-b', '--batch', '-n', '--nand_title'},
    ),
    'flycast': GameSettingsSupport(widescreenArgs: (on) => ['-config', 'config:rend.WideScreen=${on ? 'yes' : 'no'}']),
    'pcsx2': GameSettingsSupport(
      widescreenKeys: (on) => {('EmuCore', 'EnableWideScreenPatches'): '$on'},
      settingsFile: (data, _) => p.join(data, 'PCSX2', 'inis', 'PCSX2.ini'),
      reserved: const {'-datapath', '-portable', '-elf', '-disc', '-bios'},
    ),
    'duckstation': GameSettingsSupport(
      widescreenKeys: (on) => {('GPU', 'WidescreenHack'): '$on', ('Display', 'AspectRatio'): on ? '16:9' : '4:3'},
      // Swapped in beside the exe for the session.
      settingsFile: (_, exeDir) => p.join(exeDir, 'settings.ini'),
      reserved: const {'-portable', '-settings', '-bios'},
    ),
    'mame': const GameSettingsSupport(
      reserved: {
        '-inipath',
        '-homepath',
        '-rompath',
        '-cfg_directory',
        '-nvram_directory',
        '-state_directory',
        '-snapshot_directory',
        '-diff_directory',
        '-comment_directory',
        '-input_directory',
      },
    ),
    'scummvm': const GameSettingsSupport(reserved: {'--config', '--savepath', '--path', '--logfile'}),
    'ryujinx': const GameSettingsSupport(reserved: {'-r', '--root-data-dir'}),
    'xenia_canary': const GameSettingsSupport(
      reserved: {'--content_root', '--storage_root', '--cache_root', '--log_file'},
    ),
    'ares': const GameSettingsSupport(reserved: {'--settings-file', '--setting'}),
    'mgba': const GameSettingsSupport(reserved: {'-c', '--config'}),
  };

  static GameSettingsSupport of(String emulatorId) => _table[emulatorId] ?? none;
}

/// The player's extra arguments for [emulatorId] that may go on its command
/// line: never one the profile's launch uses ([GameSettingsSupport.reserved])
/// and never a file or folder (a path would let a game reach outside its
/// profile or start another game).
List<String> allowedExtraArgs(String emulatorId, String text) {
  final reserved = GameSettingsSupport.of(emulatorId).reserved;
  final out = <String>[];
  for (final a in splitArgs(text)) {
    final name = a.split('=').first.toLowerCase();
    final pathLike = a.contains(':') || a.contains(r'\') || a.contains('/') || a.contains('..');
    if (reserved.contains(name) || pathLike) {
      debugPrint('[GameSettings] $emulatorId: extra argument left out: $a');
      continue;
    }
    out.add(a);
  }
  return out;
}

/// RetroArch's shader folder beside its exe.
String retroArchShaderDir(String exeDir) => p.join(exeDir, 'shaders');

/// The shader presets RetroArch has (`.slangp`, `.glslp`, `.cgp`), relative
/// to [shaderDir] with `/`, sorted; none when it has no folder. Read in
/// another isolate: RetroArch ships thousands of files there.
Future<List<String>> retroArchShaders(String shaderDir) => Isolate.run(() {
  final dir = io.Directory(shaderDir);
  if (!dir.existsSync()) return const <String>[];
  return [
    for (final e in dir.listSync(recursive: true, followLinks: false))
      if (e is io.File && const {'.slangp', '.glslp', '.cgp'}.contains(p.extension(e.path).toLowerCase()))
        p.relative(e.path, from: shaderDir).replaceAll(r'\', '/'),
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
});

/// The arguments [s] adds for [emulatorId], before the strategy's:
/// RetroArch's `--set-shader` (only when the preset is there), widescreen
/// for this launch where the emulator takes it as an argument, then the
/// player's own that are allowed.
List<String> gameSettingArgs(String emulatorId, GameSettings s, String exeDir) {
  final support = GameSettingsSupport.of(emulatorId);
  final shader = support.shaders ? s.shader : null;
  final shaderFile = shader == null ? null : p.joinAll([retroArchShaderDir(exeDir), ...shader.split(RegExp(r'[\\/]'))]);
  return [
    if (shaderFile != null && io.File(shaderFile).existsSync()) ...['--set-shader', shaderFile],
    if (s.widescreen != Widescreen.emulator && support.widescreenArgs != null)
      ...support.widescreenArgs!(s.widescreen == Widescreen.on),
    ...allowedExtraArgs(emulatorId, s.args),
  ];
}

String _marker(String data) => p.join(data, '.gargosy-game-settings.json');

/// Sets the game's widescreen in the emulator's own settings file for this
/// session (PCSX2, DuckStation: neither takes it on the command line), run
/// after the launch config's `prepare`. The player's own values are kept in
/// `<data>\.gargosy-game-settings.json`, put back by [restoreGameSettingKeys]
/// when the game ends (or at the next launch after a crash).
void applyGameSettingKeys(String emulatorId, GameSettings s, String data, String exeDir, PathGuard guard) {
  final support = GameSettingsSupport.of(emulatorId);
  final keysOf = support.widescreenKeys;
  final fileOf = support.settingsFile;
  if (keysOf == null || fileOf == null) return;
  // Whatever an earlier session left (Gargosy closed before the game did).
  restoreGameSettingKeys(emulatorId, data, exeDir, guard);
  if (s.widescreen == Widescreen.emulator) return;
  final file = io.File(guard.check(fileOf(data, exeDir)));
  final ini = IniFile(file.existsSync() ? file.readAsStringSync() : '');
  final kept = <String, Object?>{};
  for (final e in keysOf(s.widescreen == Widescreen.on).entries) {
    kept['${e.key.$1}.${e.key.$2}'] = ini.get(e.key.$1, e.key.$2);
    ini.set(e.key.$1, e.key.$2, e.value);
  }
  final marker = io.File(guard.check(_marker(data)));
  marker.parent.createSync(recursive: true);
  marker.writeAsStringSync(jsonEncode(kept));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(ini.toText());
}

/// Puts back the values [applyGameSettingKeys] changed, if any: when the
/// game ends (before the launch config's `finish` takes the file back to
/// the profile), and before the next launch. A file gone takes the record
/// with it.
void restoreGameSettingKeys(String emulatorId, String data, String exeDir, PathGuard guard) {
  final fileOf = GameSettingsSupport.of(emulatorId).settingsFile;
  final marker = io.File(guard.check(_marker(data)));
  if (fileOf == null || !marker.existsSync()) return;
  Map<String, Object?> kept;
  try {
    kept = Map<String, Object?>.from(jsonDecode(marker.readAsStringSync()) as Map);
  } on Object {
    kept = {};
  }
  final file = io.File(guard.check(fileOf(data, exeDir)));
  if (file.existsSync() && kept.isNotEmpty) {
    final ini = IniFile(file.readAsStringSync());
    for (final e in kept.entries) {
      final dot = e.key.indexOf('.');
      if (dot <= 0) continue;
      final section = e.key.substring(0, dot);
      final key = e.key.substring(dot + 1);
      final was = e.value;
      if (was is String) {
        ini.set(section, key, was);
      } else {
        ini.remove(section, key);
      }
    }
    file.writeAsStringSync(ini.toText());
  }
  marker.deleteSync();
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
