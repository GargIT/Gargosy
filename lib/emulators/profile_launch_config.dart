import 'dart:convert';
import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/storage/ini_file.dart';
import '../profiles/path_guard.dart';
import 'config_files.dart';

/// Where one launch happens: the profile's data folder for the emulator, the
/// emulator's install folder and the shared BIOS folder.
class LaunchContext {
  const LaunchContext({
    required this.data,
    required this.exeDir,
    required this.bios,
    required this.profileId,
    required this.profilesDir,
    required this.guard,
  });

  final String data;
  final String exeDir;
  final String bios;
  final String profileId;
  final String profilesDir;
  final PathGuard guard;
}

class UnsupportedEmulatorException implements Exception {
  const UnsupportedEmulatorException(this.emulatorId);
  final String emulatorId;

  @override
  String toString() => "Gargosy can't start $emulatorId with a profile's own data yet.";
}

/// How an emulator is started on a profile's data (spec §6,
/// docs/emulator-profiles.md): arguments, and files written before launch.
abstract class ProfileLaunchConfig {
  const ProfileLaunchConfig();

  /// Readies [c] and returns the arguments that go before the strategy's own.
  Future<List<String>> prepare(LaunchContext c);

  /// After the emulator exits.
  Future<void> finish(LaunchContext c) async {}

  /// Rewrites the folder paths in the profile's stored settings to where
  /// they are now (the Gargosy folder may have moved), without starting
  /// anything. Runs before the save pull, so the save code reads this
  /// profile's folders and never an old location's.
  void repoint(LaunchContext c) {}

  static final Map<String, ProfileLaunchConfig> _configs = {
    'dolphin': _Args((c) => ['--user=${c.data}']),
    'pcsx2': _Args((c) => ['-datapath', c.data], before: (c) => _turnOff(c, const ['portable.txt', 'portable.ini'])),
    'retroarch': const _RetroArch(),
    'mame': _Args((c) => [
          '-inipath', c.data,
          '-homepath', c.data,
          '-cfg_directory', p.join(c.data, 'cfg'),
          '-nvram_directory', p.join(c.data, 'nvram'),
          '-state_directory', p.join(c.data, 'sta'),
          '-input_directory', p.join(c.data, 'inp'),
          '-snapshot_directory', p.join(c.data, 'snap'),
          '-diff_directory', p.join(c.data, 'diff'),
          '-comment_directory', p.join(c.data, 'comments'),
        ]),
    'xenia_canary': _Args((c) => [
          '--content_root=${p.join(c.data, 'content')}',
          '--storage_root=${p.join(c.data, 'storage')}',
          '--cache_root=${p.join(c.data, 'cache')}',
          '--log_file=${p.join(c.data, 'xenia.log')}',
        ]),
    'ares': _Args((c) => [
          '--settings-file', p.join(c.data, 'settings.bml'),
          '--setting', 'Paths/Saves=${p.join(c.data, 'saves')}\\',
          '--setting', 'Paths/Firmware=${c.bios}\\',
        ]),
    'xemu': const _Xemu(),
    'ppsspp': const _Ppsspp(),
    'duckstation': const _Swap(['settings.ini'], marker: 'portable.txt', edit: _duckstationFolders),
    'mgba': _Swap(const ['config.ini', 'qt.ini'], marker: 'portable.ini', args: (c) => [
          '-C', 'savegamePath=${p.join(c.data, 'saves')}',
          '-C', 'savestatePath=${p.join(c.data, 'states')}',
        ]),
    'flycast': _Swap(const ['emu.cfg'], createMissing: true, args: (c) => [
          '-config',
          'config:Dreamcast.SavePath=${p.join(c.data, 'saves')},'
              'config:Dreamcast.VMUPath=${p.join(c.data, 'vmu')},'
              'config:Dreamcast.SavestatePath=${p.join(c.data, 'states')}',
        ]),
  };

  static Set<String> get supported => _configs.keys.toSet();

  static ProfileLaunchConfig? of(String emulatorId) => _configs[emulatorId];
}

Future<void> _ensure(LaunchContext c) => io.Directory(c.guard.check(c.data)).create(recursive: true);

/// Renames files next to the exe that would make the emulator ignore the
/// profile folder (portable markers).
Future<void> _turnOff(LaunchContext c, List<String> names) async {
  for (final n in names) {
    final f = io.File(p.join(c.exeDir, n));
    if (f.existsSync()) f.renameSync(c.guard.check('${f.path}.gargosy-off'));
  }
}

class _Args extends ProfileLaunchConfig {
  const _Args(this.args, {this.before});
  final List<String> Function(LaunchContext) args;
  final Future<void> Function(LaunchContext)? before;

  @override
  Future<List<String>> prepare(LaunchContext c) async {
    await _ensure(c);
    if (before != null) await before!(c);
    return args(c);
  }
}

class _RetroArch extends ProfileLaunchConfig {
  const _RetroArch();

  /// The profile's own system folder: cores keep saves there too (LRPS2's
  /// shared memory cards), so it can't be the shared `bios\`.
  static String systemDir(LaunchContext c) => p.join(c.data, 'system');

  @override
  Future<List<String>> prepare(LaunchContext c) async {
    await _ensure(c);
    final cfg = _write(c);
    _copyBios(c.bios, systemDir(c), c.guard);
    return ['--config=${cfg.path}'];
  }

  @override
  void repoint(LaunchContext c) {
    if (io.File(p.join(c.data, 'retroarch.cfg')).existsSync()) _write(c);
  }

  io.File _write(LaunchContext c) {
    io.Directory(c.guard.check(c.data)).createSync(recursive: true);
    final cfg = io.File(c.guard.check(p.join(c.data, 'retroarch.cfg')));
    final text = cfg.existsSync() ? cfg.readAsStringSync() : '';
    cfg.writeAsStringSync(setRetroArchKeys(text, {
      'savefile_directory': p.join(c.data, 'saves'),
      'savestate_directory': p.join(c.data, 'states'),
      'system_directory': systemDir(c),
      'playlist_directory': p.join(c.data, 'playlists'),
      'content_history_directory': p.join(c.data, 'playlists'),
      'input_remapping_directory': p.join(c.data, 'config', 'remaps'),
      'rgui_config_directory': p.join(c.data, 'config'),
      'log_dir': p.join(c.data, 'logs'),
      'core_info_cache_enable': 'false',
      'config_save_on_exit': 'true',
    }));
    return cfg;
  }
}

/// Copies the shared BIOS files into [to] where they are missing or differ
/// in size. Nothing in [to] is removed (a core's own files stay).
void _copyBios(String from, String to, PathGuard guard) {
  final src = io.Directory(from);
  if (!src.existsSync()) return;
  for (final e in src.listSync(recursive: true)) {
    if (e is! io.File) continue;
    final dest = io.File(guard.check(p.join(to, p.relative(e.path, from: from))));
    if (dest.existsSync() && dest.lengthSync() == e.lengthSync()) continue;
    dest.parent.createSync(recursive: true);
    e.copySync(dest.path);
  }
}

class _Xemu extends ProfileLaunchConfig {
  const _Xemu();

  @override
  Future<List<String>> prepare(LaunchContext c) async {
    await _ensure(c);
    final toml = io.File(c.guard.check(p.join(c.data, 'xemu.toml')));
    final text = toml.existsSync() ? toml.readAsStringSync() : '';
    toml.writeAsStringSync(setTomlKeys(text, 'sys.files', {
      'eeprom_path': p.join(c.data, 'eeprom.bin'),
      'hdd_path': p.join(c.data, 'xbox_hdd.qcow2'),
    }));
    return ['-config_path', toml.path];
  }
}

class _Ppsspp extends ProfileLaunchConfig {
  const _Ppsspp();

  @override
  Future<List<String>> prepare(LaunchContext c) async {
    await _ensure(c);
    final memstick = io.Directory(p.join(c.exeDir, 'memstick'));
    if (memstick.existsSync()) memstick.renameSync(c.guard.check('${memstick.path}.gargosy-off'));
    io.File(c.guard.check(p.join(c.exeDir, 'installed.txt'))).writeAsStringSync(c.data);
    return const [];
  }
}

/// DuckStation's folder keys, all inside the profile, and the shared BIOS.
IniFile _duckstationFolders(IniFile ini, LaunchContext c) {
  ini.set('MemoryCards', 'Directory', p.join(c.data, 'memcards'));
  ini.set('BIOS', 'SearchDirectory', c.bios);
  for (final key in const [
    'Cache', 'Cheats', 'Covers', 'GameIcons', 'GameSettings', 'InputProfiles', 'Patches',
    'SaveStates', 'Screenshots', 'Shaders', 'Subchannels', 'Textures', 'UserResources', 'Videos',
  ]) {
    ini.set('Folders', key, p.join(c.data, key.toLowerCase()));
  }
  return ini;
}

/// Settings files that only live next to the exe: the profile's copies are
/// put there for a launch and taken back after it (settings only, never saves).
class _Swap extends ProfileLaunchConfig {
  const _Swap(this.files, {this.marker, this.args, this.edit, this.createMissing = false});

  final List<String> files;

  /// A file that keeps the emulator portable (data next to its exe).
  final String? marker;
  final List<String> Function(LaunchContext)? args;
  final IniFile Function(IniFile, LaunchContext)? edit;
  final bool createMissing;

  static const _swapFile = '.gargosy-swap';

  /// Puts back files a previous launch left next to the exe (Gargosy closed
  /// before the game did) into the profile they belong to.
  void _recover(LaunchContext c) {
    final mark = io.File(p.join(c.exeDir, _swapFile));
    if (!mark.existsSync()) return;
    try {
      final json = jsonDecode(mark.readAsStringSync()) as Map<String, dynamic>;
      final owner = json['profile'] as String;
      // The emulator's folder in the profile; the exe may sit in a subfolder
      // of its install, so it isn't the exe folder's name.
      final emulator = json['emulator'] as String? ?? p.basename(c.data);
      final ownerData = p.join(c.profilesDir, owner, 'emulators', emulator);
      final ownerGuard = PathGuard(c.guard.root, activeProfileId: owner);
      if (io.Directory(p.join(c.profilesDir, owner)).existsSync()) {
        io.Directory(ownerGuard.check(ownerData)).createSync(recursive: true);
        for (final f in files) {
          final live = io.File(p.join(c.exeDir, f));
          if (live.existsSync()) live.copySync(ownerGuard.check(p.join(ownerData, f)));
        }
      }
    } on Object {
      // An unreadable marker: the files stay where they are and are replaced below.
    }
    mark.deleteSync();
  }

  @override
  Future<List<String>> prepare(LaunchContext c) async {
    await _ensure(c);
    _recover(c);
    for (final f in files) {
      final mine = io.File(p.join(c.data, f));
      final live = io.File(c.guard.check(p.join(c.exeDir, f)));
      if (mine.existsSync()) {
        mine.copySync(live.path);
      } else if (live.existsSync()) {
        live.deleteSync(); // another profile's settings never reach this one
      }
      if (edit != null) {
        final ini = edit!(IniFile(live.existsSync() ? live.readAsStringSync() : ''), c);
        live.writeAsStringSync(ini.toText());
      } else if (createMissing && !live.existsSync()) {
        live.writeAsStringSync('');
      }
    }
    if (marker != null) {
      final m = io.File(c.guard.check(p.join(c.exeDir, marker!)));
      if (!m.existsSync()) m.writeAsStringSync('');
    }
    io.File(c.guard.check(p.join(c.exeDir, _swapFile))).writeAsStringSync(jsonEncode({'profile': c.profileId, 'emulator': p.basename(c.data)}));
    return args?.call(c) ?? const [];
  }

  @override
  void repoint(LaunchContext c) {
    if (edit == null) return;
    for (final f in files) {
      final mine = io.File(c.guard.check(p.join(c.data, f)));
      if (mine.existsSync()) mine.writeAsStringSync(edit!(IniFile(mine.readAsStringSync()), c).toText());
    }
  }

  @override
  Future<void> finish(LaunchContext c) async {
    for (final f in files) {
      final live = io.File(p.join(c.exeDir, f));
      if (live.existsSync()) live.copySync(c.guard.check(p.join(c.data, f)));
    }
    final mark = io.File(p.join(c.exeDir, _swapFile));
    if (mark.existsSync()) mark.deleteSync();
  }
}
