import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/emulators/fullscreen.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_secret_store.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  test('on by default; set per emulator', () async {
    final prefs = MemoryPrefs();
    expect(Fullscreen.isOn(prefs, 'pcsx2'), isTrue);
    await Fullscreen.set(prefs, 'pcsx2', false);
    expect(Fullscreen.isOn(prefs, 'pcsx2'), isFalse);
    expect(Fullscreen.isOn(prefs, 'dolphin'), isTrue);
  });

  test('every emulator Gargosy starts on a profile has a full screen flag', () {
    for (final id in ProfileLaunchConfig.supported) {
      expect(Fullscreen.supports(id), isTrue, reason: id);
    }
    expect(Fullscreen.supports('windows_native'), isFalse);
  });

  test("PCSX2 and DuckStation: off takes out their own -fullscreen and says -nofullscreen", () {
    for (final id in ['pcsx2', 'duckstation']) {
      final off = Fullscreen.apply(id, false, ['-datapath', 'x', '-batch', '-fullscreen']);
      expect(off, isNot(contains('-fullscreen')), reason: id);
      expect(off, contains('-nofullscreen'), reason: id);
      expect(off.sublist(off.length - 3), ['-datapath', 'x', '-batch'], reason: id);
      final on = Fullscreen.apply(id, true, ['-batch', '-fullscreen']);
      expect(on.where((a) => a == '-fullscreen').length, 1, reason: id);
      expect(on, isNot(contains('-nofullscreen')), reason: id);
    }
  });

  test('the flag goes first, so a strategy argument that takes the ROM next (Dolphin -e) stays last', () {
    expect(Fullscreen.apply('dolphin', false, ['--user=x', '-b', '-e']), [
      '-C',
      'Dolphin.Display.Fullscreen=False',
      '--user=x',
      '-b',
      '-e',
    ]);
    expect(Fullscreen.apply('dolphin', true, ['-b', '-e']), ['-C', 'Dolphin.Display.Fullscreen=True', '-b', '-e']);
  });

  test('each emulator its own way', () {
    expect(Fullscreen.apply('mame', false, const []), ['-window']);
    expect(Fullscreen.apply('mame', true, const []), ['-nowindow']);
    expect(Fullscreen.apply('ppsspp', false, const []), ['--windowed']);
    expect(Fullscreen.apply('ppsspp', true, const []), ['--fullscreen']);
    expect(Fullscreen.apply('xenia_canary', false, const []), ['--fullscreen=false']);
    expect(Fullscreen.apply('retroarch', true, const []), ['--fullscreen']);
    expect(Fullscreen.apply('retroarch', false, const []), isEmpty);
    expect(Fullscreen.apply('xemu', true, const ['-dvd_path']), ['-full-screen', '-dvd_path']);
    expect(Fullscreen.apply('flycast', true, const []), ['-config', 'window:fullscreen=yes']);
    expect(Fullscreen.apply('mgba', true, const []), ['-f']);
    expect(Fullscreen.apply('ares', true, const []), ['--fullscreen']);
    expect(Fullscreen.apply('windows_native', true, const ['x']), ['x']);
  });

  group('the launch', () {
    late AppRoot root;
    setUp(() async => root = await tempAppRoot());
    tearDown(() => io.Directory(root.root).deleteSync(recursive: true));

    Future<List<String>> launch(String id, String exeName, List<String> strategyArgs, {bool? fullscreen}) async {
      final prefs = MemoryPrefs();
      if (fullscreen != null) await Fullscreen.set(prefs, id, fullscreen);
      final exe = io.File(p.join(root.emulators, id, exeName))..createSync(recursive: true);
      final started = <List<String>>[];
      final dirs = ProfileLaunchDirectories(
        secrets: FakeSecretStore(),
        root: root,
        paths: ProfilePaths(root, 'aaa'),
        prefs: prefs,
        start: (exePath, args, {workingDirectory, environment}) async {
          started.add(args);
          return io.Process.start('cmd.exe', ['/c', 'exit', '0']);
        },
      );
      await dirs.launchGameWithHandle(game(1, 'G'), r'D:\roms\g.iso', id, exe.path, args: strategyArgs);
      return started.single;
    }

    test("starts PCSX2 windowed when the profile turned it off", () async {
      final args = await launch('pcsx2', 'pcsx2-qt.exe', ['-batch', '-fullscreen'], fullscreen: false);
      expect(args, contains('-nofullscreen'));
      expect(args, isNot(contains('-fullscreen')));
      expect(args.last, r'D:\roms\g.iso');
    });

    test('Dolphin full screen by default, its -e still right before the ROM', () async {
      final args = await launch('dolphin', 'Dolphin.exe', ['-b', '-e']);
      expect(args.take(2), ['-C', 'Dolphin.Display.Fullscreen=True']);
      expect(args.sublist(args.length - 2), ['-e', r'D:\roms\g.iso']);
    });

    test("RetroArch's config says windowed when off (it keeps what it saved otherwise)", () async {
      await launch('retroarch', 'retroarch.exe', const [], fullscreen: false);
      final cfg = io.File(p.join(ProfilePaths(root, 'aaa').emulatorDir('retroarch'), 'retroarch.cfg'))
          .readAsStringSync();
      expect(cfg, contains('video_fullscreen = "false"'));
    });
  });
}
