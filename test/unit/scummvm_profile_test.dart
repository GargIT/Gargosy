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

  test('--config and --savepath into the profile; screenshots in its scummvm.ini, other keys kept', () async {
    final c = ctx();
    io.File(p.join(c.data, 'scummvm.ini'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[scummvm]\ngfx_mode=opengl\n\n[monkey1]\ndescription=The Secret of Monkey Island\n');
    expect(await ProfileLaunchConfig.of('scummvm')!.prepare(c), [
      '--config=${p.join(c.data, 'scummvm.ini')}',
      '--savepath=${p.join(c.data, 'saves')}',
    ]);
    final ini = IniFile(io.File(p.join(c.data, 'scummvm.ini')).readAsStringSync());
    expect(ini.get('scummvm', 'screenshotpath'), p.join(c.data, 'screenshots'));
    expect(ini.get('scummvm', 'savepath'), p.join(c.data, 'saves'));
    expect(ini.get('scummvm', 'gfx_mode'), 'opengl');
    expect(ini.get('monkey1', 'description'), 'The Secret of Monkey Island');
    expect(io.Directory(p.join(c.data, 'saves')).existsSync(), isTrue);
  });

  test('the game: --auto-detect --path=<the game folder>, last', () {
    final folder = io.Directory(p.join(root.roms, 'scummvm', 'Monkey Island'))..createSync(recursive: true);
    final c = ctx();
    expect(ProfileLaunchConfig.of('scummvm')!.gameArgs(c, folder.path), ['--auto-detect', '--path=${folder.path}']);
    expect(ProfileLaunchConfig.of('scummvm')!.gameArgs(c, p.join(folder.path, 'MONKEY.000')),
        ['--auto-detect', '--path=${folder.path}'], reason: 'a file inside picked: its folder');
    expect(Fullscreen.supports('scummvm'), isTrue);
  });

  test("two profiles' saves and configs are apart", () async {
    final a = await ProfileLaunchConfig.of('scummvm')!.prepare(ctx(profile: 'aaa'));
    final b = await ProfileLaunchConfig.of('scummvm')!.prepare(ctx(profile: 'bbb'));
    expect(a, isNot(b));
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
      '--savepath=${p.join(data, 'saves')}',
      '--auto-detect',
      '--path=${p.absolute(p.normalize(folder.path))}',
    ]);
  });
}
