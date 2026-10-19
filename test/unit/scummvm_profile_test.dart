// Issue #11: ScummVM on a profile's data, through the shared launch path.
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategies/scummvm_strategy.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/storage/ini_file.dart';
import 'package:gargosy/emulators/fullscreen.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

/// A process that has ended.
class _Ended implements io.Process {
  @override
  Future<int> get exitCode async => 0;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppRoot root;
  setUp(() async => root = await tempAppRoot());
  tearDown(() => deleteTempDir(root.root));

  LaunchContext ctx({String profile = 'aaa'}) {
    final exeDir = p.join(root.emulators, 'scummvm');
    io.Directory(exeDir).createSync(recursive: true);
    return LaunchContext(
      data: ProfilePaths(root, profile).emulatorDir('scummvm'),
      exeDir: exeDir,
      bios: root.bios,
      profileId: profile,
      profilesDir: root.profiles,
      guard: PathGuard(root, activeProfileId: profile),
    );
  }

  test('--config into the profile; saves and screenshots in its scummvm.ini, other keys kept', () async {
    final c = ctx();
    io.File(p.join(c.data, 'scummvm.ini'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[scummvm]\ngfx_mode=opengl\n\n[monkey1]\ndescription=The Secret of Monkey Island\n');
    expect(await ProfileLaunchConfig.of('scummvm')!.prepare(c), [
      '--config=${p.join(c.data, 'scummvm.ini')}',
      '--logfile=${p.join(c.data, 'scummvm.log')}',
    ]);
    final ini = IniFile(io.File(p.join(c.data, 'scummvm.ini')).readAsStringSync());
    expect(ini.get('scummvm', 'screenshotpath'), p.join(c.data, 'screenshots'));
    expect(ini.get('scummvm', 'savepath'), p.join(c.data, 'saves'));
    expect(ini.get('scummvm', 'gfx_mode'), 'opengl');
    expect(ini.get('monkey1', 'description'), 'The Secret of Monkey Island');
    expect(io.Directory(p.join(c.data, 'saves')).existsSync(), isTrue);
  });

  test("the game: its own save folder, then --auto-detect --path=<the game folder>, last", () {
    final folder = io.Directory(p.join(root.roms, 'scummvm', 'Monkey Island'))..createSync(recursive: true);
    final c = ctx();
    final saves = '--savepath=${p.join(c.data, 'saves', 'Monkey Island')}';
    expect(ProfileLaunchConfig.of('scummvm')!.gameArgs(c, folder.path), [
      saves,
      '--auto-detect',
      '--path=${folder.path}',
    ]);
    expect(ProfileLaunchConfig.of('scummvm')!.gameArgs(c, p.join(folder.path, 'MONKEY.000')), [
      saves,
      '--auto-detect',
      '--path=${folder.path}',
    ], reason: 'a file inside picked: its folder, the same saves');
    expect(io.Directory(p.join(c.data, 'saves', 'Monkey Island')).existsSync(), isTrue);
    expect(Fullscreen.supports('scummvm'), isTrue);
  });

  test("two profiles' saves and configs are apart: every path is in the profile's own folder", () async {
    for (final profile in ['aaa', 'bbb']) {
      final c = ctx(profile: profile);
      final folder = io.Directory(p.join(root.roms, 'scummvm', 'Monkey Island'))..createSync(recursive: true);
      final args = [
        ...await ProfileLaunchConfig.of('scummvm')!.prepare(c),
        ...ProfileLaunchConfig.of('scummvm')!.gameArgs(c, folder.path).where((a) => a.startsWith('--savepath=')),
      ];
      for (final a in args) {
        final path = a.substring(a.indexOf('=') + 1);
        expect(p.isWithin(c.data, path), isTrue, reason: '$profile: $a');
      }
      final ini = IniFile(io.File(p.join(c.data, 'scummvm.ini')).readAsStringSync());
      for (final key in ['savepath', 'screenshotpath', 'iconspath']) {
        expect(p.isWithin(c.data, ini.get('scummvm', key)!), isTrue, reason: '$profile: $key');
      }
    }
  });

  test('its log goes to the profile, not %APPDATA%\\ScummVM', () async {
    final c = ctx();
    expect(await ProfileLaunchConfig.of('scummvm')!.prepare(c), contains('--logfile=${p.join(c.data, 'scummvm.log')}'));
  });

  test("RomM's .scummvm file names the game: its id, in its folder", () {
    final dir = io.Directory(p.join(root.roms, 'scummvm', 'Monkey Island'))..createSync(recursive: true);
    final svm = io.File(p.join(dir.path, 'monkey.scummvm'))..writeAsStringSync('monkey1\n');
    final c = ctx();
    expect(ProfileLaunchConfig.of('scummvm')!.gameArgs(c, svm.path), [
      '--savepath=${p.join(c.data, 'saves', 'Monkey Island')}',
      '--path=${dir.path}',
      'monkey1',
    ]);
  });

  test('a zip that unpacked into a folder of one folder: ScummVM looks in the inner one', () {
    final outer = io.Directory(p.join(root.roms, 'scummvm', 'Monkey Island (1990)'));
    final inner = io.Directory(p.join(outer.path, 'Monkey Island'))..createSync(recursive: true);
    io.File(p.join(inner.path, 'MONKEY.000')).createSync();
    final c = ctx();
    expect(ProfileLaunchConfig.of('scummvm')!.gameArgs(c, outer.path), [
      '--savepath=${p.join(c.data, 'saves', 'Monkey Island (1990)')}',
      '--auto-detect',
      '--path=${inner.path}',
    ]);
  });

  test('in a profile the strategy launches through the launch view: full screen, profile, game, in order', () async {
    final exe = io.File(p.join(root.emulators, 'scummvm', 'scummvm.exe'))..createSync(recursive: true);
    final folder = io.Directory(p.join(root.roms, 'scummvm', 'Monkey Island'))..createSync(recursive: true);
    final started = <List<String>>[];
    final dirs = ProfileLaunchDirectories(
      root: root,
      paths: ProfilePaths(root, 'aaa'),
      prefs: MemoryPrefs(),
      start: (exePath, args, {workingDirectory, environment}) async {
        started.add([exePath, ...args]);
        return _Ended();
      },
    );
    final strategy = ScummVMStrategy(dirs, platform: const PlatformInfo('windows'));
    final game = Game(id: '1', name: 'Monkey Island', fsName: 'Monkey Island', platformSlug: 'scummvm', fileSize: 0);
    await strategy.launchWithHandle(game, folder.path);
    final data = ProfilePaths(root, 'aaa').emulatorDir('scummvm');
    expect(started.single, [
      exe.path,
      '-f',
      '--config=${p.join(data, 'scummvm.ini')}',
      '--logfile=${p.join(data, 'scummvm.log')}',
      '--savepath=${p.join(data, 'saves', 'Monkey Island')}',
      '--auto-detect',
      '--path=${p.absolute(p.normalize(folder.path))}',
    ]);
  });
}
