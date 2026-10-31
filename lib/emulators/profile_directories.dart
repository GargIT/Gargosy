import '../core/storage/ini_file.dart';
import 'config_files.dart';
import '../core/emulator/platform_slugs.dart';
import '../core/emulator/emulator_registry_data.dart';
import '../core/emulator/emulator_strategy.dart';
import '../core/retroachievements/retroachievements_emulator_login.dart';

import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/platform/platform_info.dart';
import '../core/romm/romm_models.dart';
import '../core/security/secret_store.dart';
import '../core/storage/app_preferences.dart';
import '../core/storage/directory_service.dart';
import '../core/storage/profile_rooted.dart';
import '../library/rom_files.dart';
import '../profiles/app_root.dart';
import '../profiles/profile_paths.dart';
import 'emulator_layout.dart';
import 'fullscreen.dart';
import 'game_settings.dart';
import 'profile_launch_config.dart';

/// Starts a process; tests pass a recorder.
/// [environment] is added to Gargosy's own (RPCS3's `RPCS3_CONFIG_DIR`).
typedef ProcessStarter = Future<io.Process> Function(
  String exe,
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
});

Future<io.Process> _defaultStart(
  String exe,
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => io.Process.start(exe, args, workingDirectory: workingDirectory, environment: environment);

/// The environment Freegosy's save code sees for a profile: Windows' user
/// folders point inside the profile, so a fallback like `%LOCALAPPDATA%\DuckStation`
/// or `Documents\PPSSPP` can only ever find this profile's data (spec §6).
PlatformInfo sandboxedPlatform(ProfilePaths paths) {
  final real = PlatformInfo.current.environment;
  return PlatformInfo(
    'windows',
    environment: {
      'APPDATA': paths.emulatorsDir,
      'LOCALAPPDATA': paths.emulatorsDir,
      'USERPROFILE': p.join(paths.emulatorsDir, '_home'),
      if (real['COMPUTERNAME'] != null) 'COMPUTERNAME': real['COMPUTERNAME']!,
      if (real['USERNAME'] != null) 'USERNAME': real['USERNAME']!,
    },
  );
}

/// Folders and ROMs as both Gargosy views share them.
mixin _GargosyFolders on DirectoryService {
  AppRoot get root;
  ProfilePaths get paths;

  /// `profiles\<id>\emulators\<emulatorId>`: this profile's data for an emulator.
  String dataDir(String emulatorId) => paths.emulatorDir(emulatorId);

  @override
  Future<String> getEmulatorAppSupportDirectory(String emulatorName, {String? platformSlug}) async {
    final id = EmulatorLayout.idForName(emulatorName) ?? emulatorName.toLowerCase();
    final layout = EmulatorLayout.of(id);
    return layout.appSupport.isEmpty ? dataDir(id) : p.join(dataDir(id), layout.appSupport);
  }

  @override
  Future<String> getEmulatorBiosDirectory(String emulatorId, {String? platformSlug}) async => root.bios;

  /// RetroArch's is the profile's own (cores keep saves in it); the rest
  /// read the shared BIOS folder.
  @override
  Future<String> getEmulatorSystemDirectory(String emulatorId, {String? platformSlug}) async =>
      emulatorId == 'retroarch' ? p.join(dataDir('retroarch'), 'system') : root.bios;

  @override
  Future<String?> getEmulatorUrlOverride(String emulatorId) async => null;

  RomFiles get _roms => RomFiles(root);

  @override
  Future<bool> isRomDownloaded(Game game) async => _roms.isDownloaded(game);

  @override
  Future<String> getRomFilePath(Game game) async => _roms.pathFor(game);

  @override
  Future<String> getRomDirectory(Game game) async => _roms.platformDir(game);
}

/// What Freegosy's save strategies see: each emulator's "install folder" is
/// a view inside the profile's data folder (EmulatorLayout), so their
/// portable-install checks land on this profile's saves.
class ProfileSaveDirectories extends DirectoryService with _GargosyFolders implements ProfileRootedDirectories {
  ProfileSaveDirectories({required this.root, required this.paths, required AppPreferences prefs})
    : super(prefs, platform: sandboxedPlatform(paths));

  @override
  final AppRoot root;
  @override
  final ProfilePaths paths;

  @override
  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async =>
      p.join(dataDir(emulatorId), EmulatorLayout.of(emulatorId).saveView, executableName);

  @override
  Future<String> getEmulatorDirectory(String emulatorId) async =>
      emulatorId == 'temp' ? p.join(root.appData, 'temp') : dataDir(emulatorId);

  @override
  Future<io.Process?> launchGameWithHandle(
    Game game,
    String romPath,
    String emulatorId,
    String exePath, {
    List<String> args = const [],
  }) => throw StateError('The save view never launches');

  @override
  Future<void> launchGame(
    Game game,
    String romPath,
    String emulatorId,
    String exePath, {
    List<String> args = const [],
  }) => throw StateError('The save view never launches');
}

/// What Freegosy's emulator strategies launch with: the real exe in
/// `emulators\<id>\` (Gargosy owns the installs, spec §6), started with the
/// profile's launch config so the emulator works on the profile's own data.
class ProfileLaunchDirectories extends DirectoryService with _GargosyFolders implements ProfileRootedDirectories {
  ProfileLaunchDirectories({
    required this.root,
    required this.paths,
    required AppPreferences prefs,
    required this.secrets,
    ProcessStarter? start,
  }) : _start = start ?? _defaultStart,
       super(prefs, platform: const PlatformInfo('windows'));

  final ProcessStarter _start;

  /// Decrypts the profile's RetroAchievements token for a launch.
  final SecretStore secrets;

  /// Makes [emulatorId]'s folders in this profile ([EmulatorLayout.ensureFolders])
  /// when it is installed ([exeName] is found): what a launch does first, done
  /// before a profile that never ran it lists RomM's states.
  Future<void> ensureDataFolders(String emulatorId, String exeName) async {
    if (await findEmulatorExecutable(emulatorId, exeName) == null) return;
    EmulatorLayout.of(emulatorId).ensureFolders(dataDir(emulatorId));
  }

  @override
  Future<io.Process?> launchGameWithHandle(
    Game game,
    String romPath,
    String emulatorId,
    String exePath, {
    List<String> args = const [],
  }) async {
    final config = ProfileLaunchConfig.of(emulatorId);
    if (config == null) throw UnsupportedEmulatorException(emulatorId);
    final c = _context(
      emulatorId,
      p.dirname(exePath),
      raLogin: await RetroAchievementsEmulatorLogin.load(prefs, secrets),
      resumeAutoState: args.contains(EmulatorStrategy.resumeAutoStateArg),
    );
    args = [
      for (final a in args)
        if (a != EmulatorStrategy.resumeAutoStateArg) a,
    ];
    final pre = await config.prepare(c);
    // The play screen's settings for this game (#234): keys in the
    // emulator's settings (put back for a game without them), and arguments
    // after the profile's, before the strategy's (Dolphin's end in `-e`,
    // which takes the game).
    final settings = GameSettingsStore(prefs).read(game.id, emulatorId);
    applyGameSettingKeys(emulatorId, settings, c.data, c.exeDir, c.guard);
    final process = await _start(
      exePath,
      [
        ...Fullscreen.apply(emulatorId, c.fullscreen, [
          ...pre,
          ...gameSettingArgs(emulatorId, settings, c.exeDir),
          ...args,
        ]),
        ...config.gameArgs(c, romPath),
      ],
      workingDirectory: c.exeDir,
      environment: config.environment(c),
    );
    // Drained, as Freegosy does: a full pipe would freeze the emulator.
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    process.exitCode.then((_) => config.finish(c));
    onGameStarted?.call(process);
    return process;
  }

  /// Told each game's emulator process as it starts (#141): the copied
  /// launch returns only once the emulator has exited, too late to close it.
  void Function(io.Process process)? onGameStarted;

  /// Opens [emulatorId]'s own window on this profile's data, with no game
  /// (Settings → Emulators, Open): the folders and settings a launch points
  /// it at, and no full screen, so its menus (controllers) are there. The
  /// profile's settings are put back when it exits, as after a game.
  Future<io.Process> openEmulator(String emulatorId, String exePath) async {
    final config = ProfileLaunchConfig.of(emulatorId);
    if (config == null) throw UnsupportedEmulatorException(emulatorId);
    final c = _context(
      emulatorId,
      p.dirname(exePath),
      raLogin: await RetroAchievementsEmulatorLogin.load(prefs, secrets),
    );
    final pre = await config.prepare(c);
    final io.Process process;
    try {
      process = await _start(exePath, pre, workingDirectory: c.exeDir, environment: config.environment(c));
    } catch (_) {
      await config.finish(c);
      rethrow;
    }
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    process.exitCode.then((_) => config.finish(c));
    return process;
  }

  /// Runs [exePath] on this profile's data with [args] and no game (RPCS3's
  /// `--installfw`, issue #10): the launch config readies the profile and
  /// gives its environment, and nothing else is added. [finish] puts the
  /// profile's settings back; the caller runs it once the process is done,
  /// and it runs here when the start fails.
  Future<({io.Process process, Future<void> Function() finish})> startWithProfile(
    String emulatorId,
    String exePath,
    List<String> args,
  ) async {
    final config = ProfileLaunchConfig.of(emulatorId);
    if (config == null) throw UnsupportedEmulatorException(emulatorId);
    final c = _context(emulatorId, p.dirname(exePath));
    await config.prepare(c);
    final io.Process process;
    try {
      process = await _start(exePath, args, workingDirectory: c.exeDir, environment: config.environment(c));
    } catch (_) {
      await config.finish(c);
      rethrow;
    }
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    return (process: process, finish: () => config.finish(c));
  }

  /// The `roms\<platform>` folders that exist for the platforms
  /// [emulatorId] plays (its definition's slugs; aliases count).
  List<String> gameFoldersFor(String emulatorId) {
    final def = kEmulatorDefinitions.where((d) => d['id'] == emulatorId).firstOrNull;
    final slugs = {for (final s in List<String>.from(def?['platform_slugs'] ?? const [])) canonicalPlatformSlug(s)};
    final roms = io.Directory(root.roms);
    if (slugs.isEmpty || !roms.existsSync()) return const [];
    return [
      for (final d in roms.listSync()..sort((a, b) => a.path.compareTo(b.path)))
        if (d is io.Directory && slugs.contains(canonicalPlatformSlug(p.basename(d.path)))) d.path,
    ];
  }

  LaunchContext _context(
    String emulatorId,
    String exeDir, {
    RetroAchievementsEmulatorLogin? raLogin,
    bool resumeAutoState = false,
  }) => LaunchContext(
    data: dataDir(emulatorId),
    exeDir: exeDir,
    bios: root.bios,
    profileId: paths.id,
    profilesDir: root.profiles,
    guard: paths.guard,
    raLogin: raLogin,
    roms: root.roms,
    gameFolders: gameFoldersFor(emulatorId),
    fullscreen: Fullscreen.isOn(prefs, emulatorId),
    resumeAutoState: resumeAutoState,
  );

  /// Takes the RetroAchievements login out of the profile's emulator
  /// settings (RetroArch's cfg; PCSX2's ini and secrets).
  void signOutRetroAchievements() {
    final cfg = io.File(paths.guard.check(p.join(dataDir('retroarch'), 'retroarch.cfg')));
    if (cfg.existsSync()) {
      cfg.writeAsStringSync(
        setRetroArchKeys(cfg.readAsStringSync(), {
          'cheevos_enable': 'false',
          'cheevos_username': '',
          'cheevos_token': '',
        }),
      );
    }
    final inis = p.join(dataDir('pcsx2'), 'PCSX2', 'inis');
    final secrets = io.File(paths.guard.check(p.join(inis, 'secrets.ini')));
    if (secrets.existsSync()) {
      final ini = IniFile(secrets.readAsStringSync())..remove('Achievements', 'Token');
      secrets.writeAsStringSync(ini.toText());
    }
    final pcsx2 = io.File(paths.guard.check(p.join(inis, 'PCSX2.ini')));
    if (pcsx2.existsSync()) {
      final ini = IniFile(pcsx2.readAsStringSync())
        ..set('Achievements', 'Enabled', 'false')
        ..remove('Achievements', 'Username')
        ..remove('Achievements', 'LoginTimestamp');
      pcsx2.writeAsStringSync(ini.toText());
    }
  }

  /// Before the save pull: the profile's stored settings point at where its
  /// folders are now (see ProfileLaunchConfig.repoint).
  void repoint(String emulatorId) =>
      ProfileLaunchConfig.of(emulatorId)?.repoint(_context(emulatorId, p.join(root.emulators, emulatorId)));

  @override
  Future<void> launchGame(
    Game game,
    String romPath,
    String emulatorId,
    String exePath, {
    List<String> args = const [],
  }) async {
    await launchGameWithHandle(game, romPath, emulatorId, exePath, args: args);
  }

  @override
  final AppRoot root;
  @override
  final ProfilePaths paths;

  @override
  Future<String> getEmulatorDirectory(String emulatorId) async =>
      emulatorId == 'temp' ? p.join(root.appData, 'temp') : p.join(root.emulators, emulatorId);

  @override
  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async {
    final dir = io.Directory(p.join(root.emulators, emulatorId));
    if (!dir.existsSync()) return null;
    final wanted = executableName.toLowerCase();
    io.File? found;
    void search(io.Directory d, int depth) {
      if (found != null || depth > 3) return;
      // Never through a folder link (issue #8): it leads into a profile's data.
      for (final e in d.listSync(followLinks: false)) {
        if (e is io.File && p.basename(e.path).toLowerCase() == wanted) {
          found = e;
          return;
        }
      }
      for (final e in d.listSync(followLinks: false)) {
        if (e is io.Directory) search(e, depth + 1);
      }
    }

    search(dir, 0);
    return found?.path;
  }
}
