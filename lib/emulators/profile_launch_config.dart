import '../core/retroachievements/retroachievements_emulator_login.dart';

import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/save/strategies/scummvm_save_strategy.dart';
import '../core/storage/ini_file.dart';
import '../profiles/path_guard.dart';
import '../profiles/profile_paths.dart';
import 'bios_links.dart';
import 'config_files.dart';
import 'linked_emulators.dart';
import 'rpcs3_config.dart';

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
    this.raLogin,
    this.roms = '',
    this.gameFolders = const [],
    this.fullscreen = true,
    this.resumeAutoState = false,
  });

  final String data;
  final String exeDir;
  final String bios;
  final String profileId;
  final String profilesDir;
  final PathGuard guard;

  /// The profile's RetroAchievements login, for emulators that sign in from
  /// their settings; null when none is connected.
  final RetroAchievementsEmulatorLogin? raLogin;

  /// The Gargosy `roms\` folder.
  final String roms;

  /// `roms\<platform>` folders of the platforms this emulator plays: added
  /// to the emulator's own game list (it's never needed to play from
  /// Gargosy, but the emulator opened on its own shows the games).
  final List<String> gameFolders;

  /// The play screen's Full screen switch for this emulator.
  final bool fullscreen;

  /// Resume of the emulator's own auto state: its "load the auto state at
  /// start" setting is on for this launch, and off for every other one
  /// (`EmulatorStrategy.resumeAutoStateArg`).
  final bool resumeAutoState;
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

  /// The arguments that name the game, last on the command line: the ROM
  /// path for every emulator but MAME.
  List<String> gameArgs(LaunchContext c, String romPath) => [romPath];

  /// After the emulator exits.
  Future<void> finish(LaunchContext c) async {}

  /// Environment variables the emulator is started with, added to
  /// Gargosy's own (RPCS3: `RPCS3_CONFIG_DIR`, issue #10).
  Map<String, String> environment(LaunchContext c) => const {};

  /// Rewrites the folder paths in the profile's stored settings to where
  /// they are now (the Gargosy folder may have moved), without starting
  /// anything. Runs before the save pull, so the save code reads this
  /// profile's folders and never an old location's.
  void repoint(LaunchContext c) {}

  static final Map<String, ProfileLaunchConfig> _configs = {
    'dolphin': _Args(
      (c) => ['--user=${c.data}'],
      before: (c) async {
        _dolphinGameFolders(c);
        _dolphinNoStopQuestion(c);
      },
    ),
    'pcsx2': _Args(
      (c) => ['-datapath', c.data],
      before: (c) async {
        await _turnOff(c, const ['portable.txt', 'portable.ini']);
        _pcsx2Settings(c);
      },
    ),
    'retroarch': const _RetroArch(),
    'mame': _Mame(
      (c) => [
        '-inipath',
        c.data,
        '-homepath',
        c.data,
        '-cfg_directory',
        p.join(c.data, 'cfg'),
        '-nvram_directory',
        p.join(c.data, 'nvram'),
        '-state_directory',
        p.join(c.data, 'sta'),
        '-input_directory',
        p.join(c.data, 'inp'),
        '-snapshot_directory',
        p.join(c.data, 'snap'),
        '-diff_directory',
        p.join(c.data, 'diff'),
        '-comment_directory',
        p.join(c.data, 'comments'),
      ],
    ),
    'xenia_canary': _Args(
      (c) => [
        '--content_root=${p.join(c.data, 'content')}',
        '--storage_root=${p.join(c.data, 'storage')}',
        '--cache_root=${p.join(c.data, 'cache')}',
        '--log_file=${p.join(c.data, 'xenia.log')}',
      ],
    ),
    'ares': _Args(
      (c) => [
        '--settings-file',
        p.join(c.data, 'settings.bml'),
        '--setting',
        'Paths/Saves=${p.join(c.data, 'saves')}\\',
        '--setting',
        'Paths/Firmware=${c.bios}\\',
      ],
    ),
    'xemu': const _Xemu(),
    'ppsspp': const _Ppsspp(),
    'duckstation': const _Swap(['settings.ini'], marker: 'portable.txt', edit: _duckstationFolders),
    'mgba': _Swap(
      const ['config.ini', 'qt.ini'],
      marker: 'portable.ini',
      args: (c) => ['-C', 'savegamePath=${p.join(c.data, 'saves')}', '-C', 'savestatePath=${p.join(c.data, 'states')}'],
    ),
    // Ryujinx (Switch, issue #9): its whole data folder by argument (Ryubing's
    // CommandLineState: -r / --root-data-dir), and the keys from bios\.
    'ryujinx': _Args((c) => ['-r', c.data], before: (c) async => _ryujinxKeys(c)),
    // Eden, Azahar, Cemu, melonDS: a folder link (issues #8, #12–#15).
    ...linkedEmulatorConfigs,
    'rpcs3': const Rpcs3Config(),
    // ScummVM (issue #11): its config by argument; each game's own save
    // folder and the game folder last (_ScummVm.gameArgs).
    'scummvm': _ScummVm(
      (c) => [
        '--config=${p.join(c.data, 'scummvm.ini')}',
        // Its log would go to %APPDATA%\ScummVM\Logs otherwise.
        '--logfile=${p.join(c.data, 'scummvm.log')}',
      ],
      before: (c) async => _scummVmFolders(c),
    ),
    'flycast': _Swap(
      const ['emu.cfg'],
      createMissing: true,
      args: (c) => [
        '-config',
        'config:Dreamcast.SavePath=${p.join(c.data, 'saves')},'
            'config:Dreamcast.VMUPath=${p.join(c.data, 'vmu')},'
            'config:Dreamcast.SavestatePath=${p.join(c.data, 'states')}',
      ],
    ),
  };

  static Set<String> get supported => _configs.keys.toSet();

  static ProfileLaunchConfig? of(String emulatorId) => _configs[emulatorId];
}

/// PCSX2 looks for BIOS files in the shared `bios\` (spec §6), not in the
/// profile's own `PCSX2\bios`, and signs in with the profile's
/// RetroAchievements login (the `[Achievements]` keys, the token in
/// secrets.ini, as Freegosy's PCSX2 strategy writes them). Only those keys
/// change; a new profile's file starts the way PCSX2 writes its own
/// (SettingsVersion 1), so PCSX2 keeps it instead of resetting it.
void _pcsx2Settings(LaunchContext c) {
  final inis = p.join(c.data, 'PCSX2', 'inis');
  final ini = io.File(c.guard.check(p.join(inis, 'PCSX2.ini')));
  final settings = IniFile(ini.existsSync() ? ini.readAsStringSync() : '');
  if (!ini.existsSync()) settings.set('UI', 'SettingsVersion', '1');
  settings.set('Folders', 'Bios', c.bios);
  // Closed by the quit buttons (#141), it shuts down at once instead of
  // asking first (the question takes it out of full screen, and waits).
  settings.set('UI', 'ConfirmShutdown', 'false');
  // Closed however (the quit buttons too), it keeps where the game was in
  // its resume state (`<serial> (<CRC>).resume.p2s`), which syncs like the
  // other states and is the newest to Resume from.
  settings.set('EmuCore', 'SaveStateOnShutdown', 'true');
  for (final f in c.gameFolders) {
    settings.add('GameList', 'RecursivePaths', f);
  }
  final ra = c.raLogin;
  io.Directory(inis).createSync(recursive: true);
  if (ra != null) {
    final newUser = settings.get('Achievements', 'Username') != ra.username;
    settings.set('Achievements', 'Enabled', 'true');
    settings.set('Achievements', 'Username', ra.username);
    if (newUser || settings.get('Achievements', 'LoginTimestamp') == null) {
      settings.set('Achievements', 'LoginTimestamp', '${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
    }
    settings.set('Achievements', 'ChallengeMode', '${ra.hardcore ?? false}');
    final secretsFile = io.File(c.guard.check(p.join(inis, 'secrets.ini')));
    final secrets = IniFile(secretsFile.existsSync() ? secretsFile.readAsStringSync() : '');
    secrets.set('Achievements', 'Token', ra.token);
    secretsFile.writeAsStringSync(secrets.toText());
  }
  ini.writeAsStringSync(settings.toText());
}

/// Dolphin's ISO folders (`Config\Dolphin.ini`, `[General] ISOPathN`):
/// Gargosy's, searched recursively, unless the player set their own.
void _dolphinGameFolders(LaunchContext c) {
  if (c.gameFolders.isEmpty) return;
  final file = io.File(c.guard.check(p.join(c.data, 'Config', 'Dolphin.ini')));
  final ini = IniFile(file.existsSync() ? file.readAsStringSync() : '');
  if ((int.tryParse(ini.get('General', 'ISOPaths') ?? '') ?? 0) > 0) return;
  ini.set('General', 'ISOPaths', '${c.gameFolders.length}');
  for (var i = 0; i < c.gameFolders.length; i++) {
    ini.set('General', 'ISOPath$i', c.gameFolders[i]);
  }
  ini.set('General', 'RecursiveISOPaths', 'True');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(ini.toText());
}

/// Dolphin stops when closed (the quit buttons, #141) without asking first:
/// `[Interface] ConfirmStop` off.
void _dolphinNoStopQuestion(LaunchContext c) {
  final file = io.File(c.guard.check(p.join(c.data, 'Config', 'Dolphin.ini')));
  final ini = IniFile(file.existsSync() ? file.readAsStringSync() : '');
  if (ini.get('Interface', 'ConfirmStop') == 'False') return;
  ini.set('Interface', 'ConfirmStop', 'False');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(ini.toText());
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

/// MAME finds a game by its set name in its rompath, never by a file path:
/// given `D:\roms\arcade\1943.zip` it looks for a set called `1943` in its
/// own `roms\` and quits. So the ROM's folder goes first in `-rompath`
/// (MAME's `roms\` after it, for BIOS sets kept there) and the set name last.
class _Mame extends _Args {
  const _Mame(super.args);

  @override
  List<String> gameArgs(LaunchContext c, String romPath) => [
    '-rompath',
    '${p.dirname(romPath)};${p.join(c.exeDir, 'roms')}',
    p.basenameWithoutExtension(romPath),
  ];
}

/// ScummVM is started on the game's folder: `--auto-detect --path=<folder>`,
/// with the game's own save folder, `<data>\saves\<game>\`: ScummVM names
/// saves by engine, so the save code tells games apart by folder.
class _ScummVm extends _Args {
  const _ScummVm(super.args, {super.before});

  @override
  List<String> gameArgs(LaunchContext c, String romPath) {
    final saves = c.guard.join(p.join(c.data, 'saves'), scummVmSaveFolderName(romPath));
    io.Directory(saves).createSync(recursive: true);
    return ['--savepath=$saves', ...scummVmGameArgs(romPath)];
  }
}

/// How ScummVM starts the game at [romPath] (issue #11):
/// - a `.scummvm`/`.svm` file (RomM's ScummVM convention: the game's id in
///   a file beside its data): that id, in the file's folder;
/// - a folder: auto-detected there, gone down through folders that hold
///   only one folder (a zip that unpacked into `<name>\<Game>\`);
/// - another file: auto-detected in its folder.
List<String> scummVmGameArgs(String romPath) {
  if (!io.Directory(romPath).existsSync()) {
    final file = io.File(romPath);
    final ext = p.extension(romPath).toLowerCase();
    if (file.existsSync() && (ext == '.scummvm' || ext == '.svm')) {
      final id = file.readAsStringSync().trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Za-z0-9:_-]+$').hasMatch(id)) return ['--path=${p.dirname(romPath)}', id];
    }
    return ['--auto-detect', '--path=${p.dirname(romPath)}'];
  }
  var dir = io.Directory(romPath);
  while (dir.existsSync()) {
    final entries = dir.listSync(followLinks: false);
    if (entries.length != 1 || entries.single is! io.Directory) break;
    dir = entries.single as io.Directory;
  }
  return ['--auto-detect', '--path=${dir.path}'];
}

/// The profile's ScummVM folders: saves (also given as --savepath) and
/// screenshots, in its own scummvm.ini; other keys are kept.
void _scummVmFolders(LaunchContext c) {
  final saves = io.Directory(c.guard.check(p.join(c.data, 'saves')))..createSync(recursive: true);
  final shots = io.Directory(c.guard.check(p.join(c.data, 'screenshots')))..createSync(recursive: true);
  final file = io.File(c.guard.check(p.join(c.data, 'scummvm.ini')));
  final ini = IniFile(file.existsSync() ? file.readAsStringSync() : '')
    ..set('scummvm', 'savepath', saves.path)
    ..set('scummvm', 'screenshotpath', shots.path)
    // Downloaded icons: the profile's, not %APPDATA%\ScummVM\Icons.
    ..set('scummvm', 'iconspath', (io.Directory(c.guard.check(p.join(c.data, 'icons')))..createSync()).path);
  file.writeAsStringSync(ini.toText());
}

/// [key] is set in RetroArch's config [text] (any value).
bool _hasKey(String text, String key) => RegExp('^\\s*$key\\s*=', multiLine: true).hasMatch(text);

class _RetroArch extends ProfileLaunchConfig {
  const _RetroArch();

  /// The profile's own system folder: cores keep saves there too (LRPS2's
  /// shared memory cards), so it can't be the shared `bios\`.
  static String systemDir(LaunchContext c) => p.join(c.data, 'system');

  @override
  Future<List<String>> prepare(LaunchContext c) async {
    await _ensure(c);
    final cfg = _write(c);
    linkBiosInto(c.bios, systemDir(c), c.guard);
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
    // Saves that RetroArch sorted into core or content subfolders come up
    // into saves\ before sorting goes off, so none is left where nothing reads.
    if (RegExp(r'^\s*sort_savefiles(_by_content)?_enable\s*=\s*"true"', multiLine: true).hasMatch(text)) {
      flattenRetroArchSaves(p.join(c.data, 'saves'), c.guard);
    }
    cfg.writeAsStringSync(
      setRetroArchKeys(text, {
        'savefile_directory': p.join(c.data, 'saves'),
        // Saves flat in saves\, never in a core or content subfolder, nor next
        // to the ROM: sigil's save root (issue #7) and the old strategy both
        // read them there, and roms\ holds only ROMs.
        'sort_savefiles_enable': 'false',
        'sort_savefiles_by_content_enable': 'false',
        'savefiles_in_content_dir': 'false',
        'savestates_in_content_dir': 'false',
        'savestate_directory': p.join(c.data, 'states'),
        // States sorted by core, as RetroArch does by default and the save code
        // assumes: pinned before its first exit writes them (state-sync plan
        // S0.2); a choice already in the profile's config stays.
        if (!_hasKey(text, 'sort_savestates_enable')) 'sort_savestates_enable': 'true',
        if (!_hasKey(text, 'sort_savestates_by_content_enable')) 'sort_savestates_by_content_enable': 'false',
        // Auto Load State only when Resume starts the auto slot, which
        // --entryslot can't load; off for every other launch, so a plain Play
        // never starts in it.
        'savestate_auto_load': '${c.resumeAutoState}',
        // Closing the game keeps where it was in the auto slot, which syncs
        // and resumes like the other states.
        'savestate_auto_save': 'true',
        'system_directory': systemDir(c),
        if (c.roms.isNotEmpty) 'rgui_browser_directory': c.roms,
        'playlist_directory': p.join(c.data, 'playlists'),
        'content_history_directory': p.join(c.data, 'playlists'),
        'input_remapping_directory': p.join(c.data, 'config', 'remaps'),
        'rgui_config_directory': p.join(c.data, 'config'),
        'log_dir': p.join(c.data, 'logs'),
        'core_info_cache_enable': 'false',
        'config_save_on_exit': 'true',
        // On is --fullscreen at launch; off has no flag, so it goes here.
        if (!c.fullscreen) 'video_fullscreen': 'false',
        // The profile's RetroAchievements login, in its own config (Gargosy
        // owns it, so RetroArch may save it on exit).
        if (c.raLogin case final ra?) ...{
          'cheevos_enable': 'true',
          'cheevos_username': ra.username,
          'cheevos_password': '',
          'cheevos_token': ra.token,
          'cheevos_hardcore_mode_enable': '${ra.hardcore ?? false}',
        },
      }),
    );
    return cfg;
  }
}

class _Xemu extends ProfileLaunchConfig {
  const _Xemu();

  @override
  Future<List<String>> prepare(LaunchContext c) async {
    await _ensure(c);
    final toml = io.File(c.guard.check(p.join(c.data, 'xemu.toml')));
    final text = toml.existsSync() ? toml.readAsStringSync() : '';
    final hdd = p.join(c.data, 'xbox_hdd.qcow2');
    _seedHdd(c, hdd);
    final bootrom = _rom(c, text, 'bootrom_path', const ['mcpx_1.0.bin']);
    final flashrom = _rom(c, text, 'flashrom_path', const ['Complex_4627.bin', 'Complex_4627v1.03.bin', 'Complex.bin']);
    toml.writeAsStringSync(
      setTomlKeys(text, 'sys.files', {
        'eeprom_path': p.join(c.data, 'eeprom.bin'),
        'hdd_path': hdd,
        'bootrom_path': ?bootrom,
        'flashrom_path': ?flashrom,
      }),
    );
    return ['-config_path', toml.path];
  }

  /// Xbox saves live on the hard disk image, so each profile has its own:
  /// the first launch copies `bios\xbox_hdd.qcow2` (RomM's firmware) in. A
  /// copy, never a link, and never again once the profile has one.
  static void _seedHdd(LaunchContext c, String hdd) {
    final blank = io.File(p.join(c.bios, 'xbox_hdd.qcow2'));
    if (io.File(hdd).existsSync() || !blank.existsSync()) return;
    blank.copySync(c.guard.check(hdd));
  }

  /// A boot or flash ROM from `bios\` for [key], unless the profile's toml
  /// already names a file that exists; null leaves the key as it is.
  static String? _rom(LaunchContext c, String text, String key, List<String> names) {
    final set = getTomlKey(text, 'sys.files', key);
    if (set != null && set.isNotEmpty && io.File(set).existsSync()) return null;
    for (final n in names) {
      final f = p.join(c.bios, n);
      if (io.File(f).existsSync()) return f;
    }
    return null;
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

/// Ryujinx's keys (RomM's firmware in `bios\`, `bios\switch` first) into
/// the profile's `system\`, where it reads them; a game can't start without
/// prod.keys. The profile's own copies: Ryujinx's Install Keys writes there,
/// which must not reach `bios\` or another profile, and newer keys a
/// profile has are never replaced.
void _ryujinxKeys(LaunchContext c) {
  final bios = BiosFiles(c.bios);
  for (final name in const ['prod.keys', 'title.keys']) {
    final file = bios.find([name], platforms: const ['switch']);
    if (file != null) copySharedFileIfMissing(file, p.join(c.data, 'system', name), c.guard);
  }
}

/// DuckStation's folder keys, all inside the profile, and the shared BIOS.
IniFile _duckstationFolders(IniFile ini, LaunchContext c) {
  ini.set('MemoryCards', 'Directory', p.join(c.data, 'memcards'));
  for (final f in c.gameFolders) {
    ini.add('GameList', 'RecursivePaths', f);
  }
  ini.set('BIOS', 'SearchDirectory', c.bios);
  // Closing the game keeps where it was in `<serial>_resume.sav`, which
  // syncs and resumes like the other states.
  ini.set('Main', 'SaveStateOnExit', 'true');
  for (final key in const [
    'Cache',
    'Cheats',
    'Covers',
    'GameIcons',
    'GameSettings',
    'InputProfiles',
    'Patches',
    'SaveStates',
    'Screenshots',
    'Shaders',
    'Subchannels',
    'Textures',
    'UserResources',
    'Videos',
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
      // Both names come from a file in the shared emulators\ folder: checked
      // before any path is built from them.
      final ownerGuard = c.guard.forProfile(owner);
      final ownerPaths = ProfilePaths(ownerGuard.root, owner);
      final ownerData = ownerPaths.emulatorDir(emulator);
      if (io.Directory(ownerPaths.dir).existsSync()) {
        io.Directory(ownerGuard.check(ownerData)).createSync(recursive: true);
        for (final f in files) {
          final live = io.File(p.join(c.exeDir, f));
          if (live.existsSync()) live.copySync(ownerGuard.check(p.join(ownerData, f)));
        }
      }
    } on Object catch (e) {
      // An unreadable marker: the files stay where they are and are replaced below.
      debugPrint('[Launch] Swap marker in ${c.exeDir} not put back: $e');
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
    io.File(c.guard.check(p.join(c.exeDir, _swapFile)))
        .writeAsStringSync(jsonEncode({'profile': c.profileId, 'emulator': p.basename(c.data)}));
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

/// Moves the saves RetroArch sorted into subfolders of [saves] (by core,
/// or by core and content folder) up into [saves], where it reads them
/// once sorting is off. A save whose name is already in [saves] stays
/// where it is: nothing is overwritten.
void flattenRetroArchSaves(String saves, PathGuard guard) {
  final dir = io.Directory(saves);
  if (!dir.existsSync()) return;
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is! io.File || p.dirname(e.path) == p.normalize(saves)) continue;
    final flat = guard.check(p.join(saves, p.basename(e.path)));
    if (io.FileSystemEntity.typeSync(flat) != io.FileSystemEntityType.notFound) continue;
    e.renameSync(flat);
  }
}
