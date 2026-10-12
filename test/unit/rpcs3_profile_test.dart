// Issue #10: RPCS3 on a profile's data through RPCS3_CONFIG_DIR, with the
// firmware shared.
import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/emulators/emulator_layout.dart';
import 'package:gargosy/emulators/fullscreen.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/emulators/ps3_firmware.dart';
import 'package:gargosy/emulators/rpcs3_config.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

/// A process that has ended with [code].
class _Ended implements io.Process {
  _Ended(this.code);
  final int code;
  @override
  Future<int> get exitCode async => code;
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
    final exeDir = p.join(root.emulators, 'rpcs3');
    io.Directory(exeDir).createSync(recursive: true);
    return LaunchContext(
      data: ProfilePaths(root, profile).emulatorDir('rpcs3'),
      exeDir: exeDir,
      bios: root.bios,
      profileId: profile,
      profilesDir: root.profiles,
      guard: PathGuard(root, activeProfileId: profile),
    );
  }

  String sharedFlash() => '${p.join(root.emulators, 'rpcs3', 'dev_flash').replaceAll(r'\', '/')}/';

  test('RPCS3_CONFIG_DIR is the profile\'s folder; other emulators get no new variables', () {
    final c = ctx();
    expect(ProfileLaunchConfig.of('rpcs3')!.environment(c), {'RPCS3_CONFIG_DIR': '${c.data}${p.separator}'});
    expect(ProfileLaunchConfig.of('dolphin')!.environment(c), isEmpty);
  });

  test("vfs.yml points /dev_flash/ at the shared firmware; the profile's other paths are kept", () async {
    final c = ctx();
    io.File(p.join(c.data, 'vfs.yml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('\$(EmulatorDir): ""\n/dev_hdd0/: \$(EmulatorDir)dev_hdd0/\n/dev_flash/: \$(EmulatorDir)dev_flash/\n');
    expect(await ProfileLaunchConfig.of('rpcs3')!.prepare(c), isEmpty);
    final vfs = io.File(p.join(c.data, 'vfs.yml')).readAsStringSync();
    expect(vfs, contains('/dev_flash/: ${sharedFlash()}\n'));
    expect(vfs, contains('/dev_hdd0/: \$(EmulatorDir)dev_hdd0/'), reason: 'saves stay in the profile');
    expect(RegExp('^/dev_flash/:', multiLine: true).allMatches(vfs).length, 1);
    expect(io.Directory(p.join(root.emulators, 'rpcs3', 'dev_flash')).existsSync(), isTrue);
  });

  test('a portable\\ beside the exe (it would win) is turned off, never deleted', () async {
    final c = ctx();
    io.File(p.join(c.exeDir, 'portable', 'config.yml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('mine');
    await ProfileLaunchConfig.of('rpcs3')!.prepare(c);
    expect(io.Directory(p.join(c.exeDir, 'portable')).existsSync(), isFalse);
    expect(io.File(p.join(c.exeDir, 'portable.gargosy-off', 'config.yml')).readAsStringSync(), 'mine');
  });

  test('repoint: the shared firmware path follows a moved Gargosy folder', () async {
    final c = ctx();
    io.File(p.join(c.data, 'vfs.yml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('/dev_flash/: D:/old/Gargosy/emulators/rpcs3/dev_flash/\n');
    ProfileLaunchConfig.of('rpcs3')!.repoint(c);
    expect(io.File(p.join(c.data, 'vfs.yml')).readAsStringSync(), '/dev_flash/: ${sharedFlash()}\n');
  });

  test("two profiles never share dev_hdd0; the save code's install is <data>", () {
    expect(ctx(profile: 'aaa').data, isNot(ctx(profile: 'bbb').data));
    expect(EmulatorLayout.of('rpcs3').saveView, '');
    expect(EmulatorLayout.of('rpcs3').seed, contains('dev_hdd0/home/00000001/savedata'));
  });

  test('full screen needs --no-gui, which also ends RPCS3 with the game', () {
    expect(Fullscreen.supports('rpcs3'), isTrue);
  });

  group('the launch and the firmware', () {
    late List<(List<String>, Map<String, String>?)> started;
    late int exitCode;
    late ProfileLaunchDirectories dirs;
    late String exe;

    setUp(() {
      started = [];
      exitCode = 0;
      exe = p.join(root.emulators, 'rpcs3', 'rpcs3.exe');
      io.File(exe).createSync(recursive: true);
      dirs = ProfileLaunchDirectories(
        root: root,
        paths: ProfilePaths(root, 'aaa'),
        prefs: MemoryPrefs(),
        start: (exePath, args, {workingDirectory, environment}) async {
          started.add((args, environment));
          if (args.first == '--installfw' && exitCode == 0) {
            io.File(p.join(root.emulators, 'rpcs3', 'dev_flash', 'vsh', 'module', 'vsh.self')).createSync(recursive: true);
          }
          return _Ended(exitCode);
        },
      );
    });

    test('a game starts with the profile\'s RPCS3_CONFIG_DIR in its environment', () async {
      await dirs.launchGameWithHandle(game(1, 'G', platform: 'ps3'), r'D:\roms\ps3\G', 'rpcs3', exe);
      expect(started.single.$2, {'RPCS3_CONFIG_DIR': '${ProfilePaths(root, 'aaa').emulatorDir('rpcs3')}${p.separator}'});
      expect(started.single.$1.last, r'D:\roms\ps3\G');
    });

    test('the firmware: rpcs3.exe --installfw <PS3UPDAT.PUP from bios\\>, on the profile, once for everyone', () async {
      final pup = io.File(p.join(root.bios, 'ps3', 'PS3UPDAT.PUP'))..createSync(recursive: true);
      final firmware = Ps3Firmware(root, dirs);
      expect(firmware.installed, isFalse);
      await firmware.install(exe);
      expect(started.single.$1, ['--installfw', pup.path]);
      expect(started.single.$2!['RPCS3_CONFIG_DIR'], isNotNull);
      expect(firmware.installed, isTrue);
    });

    test('no PS3UPDAT.PUP in bios\\: a clear message, nothing started', () async {
      await expectLater(Ps3Firmware(root, dirs).install(exe),
          throwsA(isA<Ps3FirmwareException>().having((e) => e.message, 'message', contains('PS3UPDAT.PUP'))));
      expect(started, isEmpty);
    });

    test('RPCS3 failing says so', () async {
      io.File(p.join(root.bios, 'PS3UPDAT.PUP')).createSync(recursive: true);
      exitCode = 1;
      await expectLater(Ps3Firmware(root, dirs).install(exe), throwsA(isA<Ps3FirmwareException>()));
    });
  });

  test('setYamlKeys: replaces or adds a top-level key, keeps the rest', () {
    expect(setYamlKeys('a: 1\nb: 2\n', {'b': '3', 'c': '4'}), 'a: 1\nb: 3\nc: 4\n');
    expect(setYamlKeys('', {'/dev_flash/': 'x/'}), '/dev_flash/: x/\n');
  });
}
