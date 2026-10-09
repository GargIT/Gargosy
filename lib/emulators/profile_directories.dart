import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/platform/platform_info.dart';
import '../core/romm/romm_models.dart';
import '../core/storage/app_preferences.dart';
import '../core/storage/directory_service.dart';
import '../core/storage/profile_rooted.dart';
import '../library/rom_files.dart';
import '../profiles/app_root.dart';
import '../profiles/profile_paths.dart';
import 'emulator_layout.dart';
import 'profile_launch_config.dart';

/// Starts a process; tests pass a recorder.
typedef ProcessStarter = Future<io.Process> Function(String exe, List<String> args, {String? workingDirectory});

Future<io.Process> _defaultStart(String exe, List<String> args, {String? workingDirectory}) =>
    io.Process.start(exe, args, workingDirectory: workingDirectory);

/// The environment Freegosy's save code sees for a profile: Windows' user
/// folders point inside the profile, so a fallback like `%LOCALAPPDATA%\DuckStation`
/// or `Documents\PPSSPP` can only ever find this profile's data (spec §6).
PlatformInfo sandboxedPlatform(ProfilePaths paths) {
  final real = PlatformInfo.current.environment;
  return PlatformInfo('windows', environment: {
    'APPDATA': paths.emulatorsDir,
    'LOCALAPPDATA': paths.emulatorsDir,
    'USERPROFILE': p.join(paths.emulatorsDir, '_home'),
    if (real['COMPUTERNAME'] != null) 'COMPUTERNAME': real['COMPUTERNAME']!,
    if (real['USERNAME'] != null) 'USERNAME': real['USERNAME']!,
  });
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
  Future<io.Process?> launchGameWithHandle(Game game, String romPath, String emulatorId, String exePath,
          {List<String> args = const []}) =>
      throw StateError('The save view never launches');

  @override
  Future<void> launchGame(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) =>
      throw StateError('The save view never launches');
}

/// What Freegosy's emulator strategies launch with: the real exe in
/// `emulators\<id>\` (Gargosy owns the installs, spec §6), started with the
/// profile's launch config so the emulator works on the profile's own data.
class ProfileLaunchDirectories extends DirectoryService with _GargosyFolders implements ProfileRootedDirectories {
  ProfileLaunchDirectories({required this.root, required this.paths, required AppPreferences prefs, ProcessStarter? start})
      : _start = start ?? _defaultStart,
        super(prefs, platform: const PlatformInfo('windows'));

  final ProcessStarter _start;

  @override
  Future<io.Process?> launchGameWithHandle(Game game, String romPath, String emulatorId, String exePath,
      {List<String> args = const []}) async {
    final config = ProfileLaunchConfig.of(emulatorId);
    if (config == null) throw UnsupportedEmulatorException(emulatorId);
    final c = _context(emulatorId, p.dirname(exePath));
    final pre = await config.prepare(c);
    final process = await _start(exePath, [...pre, ...args, romPath], workingDirectory: c.exeDir);
    // Drained, as Freegosy does: a full pipe would freeze the emulator.
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    process.exitCode.then((_) => config.finish(c));
    return process;
  }

  LaunchContext _context(String emulatorId, String exeDir) => LaunchContext(
        data: dataDir(emulatorId),
        exeDir: exeDir,
        bios: root.bios,
        profileId: paths.id,
        profilesDir: root.profiles,
        guard: paths.guard,
      );

  /// Before the save pull: the profile's stored settings point at where its
  /// folders are now (see ProfileLaunchConfig.repoint).
  void repoint(String emulatorId) =>
      ProfileLaunchConfig.of(emulatorId)?.repoint(_context(emulatorId, p.join(root.emulators, emulatorId)));

  @override
  Future<void> launchGame(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
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
      for (final e in d.listSync()) {
        if (e is io.File && p.basename(e.path).toLowerCase() == wanted) {
          found = e;
          return;
        }
      }
      for (final e in d.listSync()) {
        if (e is io.Directory) search(e, depth + 1);
      }
    }

    search(dir, 0);
    return found?.path;
  }
}
