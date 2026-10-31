import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/core/storage/ini_file.dart';
import 'package:gargosy/emulators/emulator_layout.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/play/screenshot_uploads.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_preferences.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_dio_adapter.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late ProfilePaths paths;
  setUp(() async {
    root = await tempAppRoot();
    paths = ProfilePaths(root, 'aaa');
  });
  tearDown(() => deleteTempDir(root.root));

  final start = DateTime(2026, 10, 31, 20);
  final end = DateTime(2026, 10, 31, 21);

  String shot(String emu, String rel, DateTime at) {
    final f = io.File(p.join(paths.emulatorDir(emu), rel))
      ..createSync(recursive: true)
      ..writeAsBytesSync([0x89, 0x50]);
    f.setLastModifiedSync(at);
    return f.path;
  }

  group('found after the game', () {
    test("images in the emulator's screenshot folders written while it ran, oldest first, with subfolders", () {
      final a = shot('dolphin', r'ScreenShots\GALE01\GALE01-2.png', start.add(const Duration(minutes: 30)));
      final b = shot('dolphin', r'ScreenShots\GALE01\GALE01-1.PNG', start.add(const Duration(minutes: 5)));
      shot('dolphin', r'ScreenShots\GALE01\old.png', start.subtract(const Duration(days: 1)));
      shot('dolphin', r'ScreenShots\GALE01\notes.txt', start.add(const Duration(minutes: 5)));
      shot('dolphin', r'StateSaves\GALE01.s01.png', start.add(const Duration(minutes: 5)));
      final layout = EmulatorLayout.of('dolphin');
      expect(screenshotsTaken(paths.emulatorDir('dolphin'), layout, start, end), [b, a]);
    });

    test('an emulator without screenshot folders, or none made yet: nothing', () {
      expect(screenshotsTaken(paths.emulatorDir('xemu'), EmulatorLayout.of('xemu'), start, end), isEmpty);
      expect(screenshotsTaken(paths.emulatorDir('retroarch'), EmulatorLayout.of('retroarch'), start, end), isEmpty);
    });
  });

  group('each emulator is told to write them where they are looked for', () {
    LaunchContext ctx(String emu) {
      final exeDir = p.join(root.emulators, emu);
      io.Directory(exeDir).createSync(recursive: true);
      return LaunchContext(
        data: paths.emulatorDir(emu),
        exeDir: exeDir,
        bios: root.bios,
        profileId: 'aaa',
        profilesDir: root.profiles,
        guard: PathGuard(root, activeProfileId: 'aaa'),
        roms: root.roms,
      );
    }

    String folder(String emu) => p.normalize(p.join(paths.emulatorDir(emu), EmulatorLayout.of(emu).screenshots.single));

    test("RetroArch: screenshot_directory, never beside the ROM", () async {
      await ProfileLaunchConfig.of('retroarch')!.prepare(ctx('retroarch'));
      final cfg = io.File(p.join(paths.emulatorDir('retroarch'), 'retroarch.cfg')).readAsStringSync();
      String? key(String k) => RegExp('^$k\\s*=\\s*"([^"]*)"', multiLine: true).firstMatch(cfg)?.group(1);
      expect(key('screenshot_directory'), folder('retroarch'));
      expect(key('screenshots_in_content_dir'), 'false');
    });

    test('mGBA: -C screenshotPath (its own default is beside the ROM)', () async {
      final args = await ProfileLaunchConfig.of('mgba')!.prepare(ctx('mgba'));
      expect(args, contains('screenshotPath=${folder('mgba')}'));
    });

    test('PCSX2: [Folders] Snapshots', () async {
      await ProfileLaunchConfig.of('pcsx2')!.prepare(ctx('pcsx2'));
      final ini = io.File(p.join(paths.emulatorDir('pcsx2'), 'PCSX2', 'inis', 'PCSX2.ini')).readAsStringSync();
      expect(IniFile(ini).get('Folders', 'Snapshots'), folder('pcsx2'));
    });

    test('DuckStation: [Folders] Screenshots', () async {
      final c = ctx('duckstation');
      final config = ProfileLaunchConfig.of('duckstation')!;
      await config.prepare(c);
      final ini = io.File(p.join(c.exeDir, 'settings.ini')).readAsStringSync();
      expect(IniFile(ini).get('Folders', 'Screenshots'), folder('duckstation'));
      await config.finish(c);
    });

    test('MAME: -snapshot_directory', () async {
      final args = await ProfileLaunchConfig.of('mame')!.prepare(ctx('mame'));
      expect(args[args.indexOf('-snapshot_directory') + 1], folder('mame'));
    });

    test("Dolphin, PPSSPP: their own folders inside the profile's data", () async {
      final dolphin = await ProfileLaunchConfig.of('dolphin')!.prepare(ctx('dolphin'));
      final user = dolphin.firstWhere((a) => a.startsWith('--user=')).substring('--user='.length);
      expect(folder('dolphin'), p.join(user, 'ScreenShots'));
      final c = ctx('ppsspp');
      await ProfileLaunchConfig.of('ppsspp')!.prepare(c);
      final stick = io.File(p.join(c.exeDir, 'installed.txt')).readAsStringSync().trim();
      expect(folder('ppsspp'), p.normalize(p.join(stick, 'PSP', 'SCREENSHOT')));
    });
  });

  group('the queue', () {
    ScreenshotUploads uploads(ProfilePreferences prefs, Future<void> Function(String, String)? send) =>
        ScreenshotUploads(prefs, upload: send);

    test('sent oldest first and forgotten once RomM has them', () async {
      final prefs = ProfilePreferences.open(paths);
      final a = shot('retroarch', r'screenshots\a.png', start);
      final b = shot('retroarch', r'screenshots\b.png', start);
      final sent = <String>[];
      final q = uploads(prefs, (game, path) async => sent.add('$game:${p.basename(path)}'));
      await q.add('7', [a, b]);
      await q.add('7', [a]);
      expect(q.waiting.length, 2, reason: 'the same file once');
      expect(await q.sendWaiting(), 2);
      expect(sent, ['7:a.png', '7:b.png']);
      expect(q.waiting, isEmpty);
    });

    test('RomM away: it stops and keeps the rest for next time; a refused or deleted file is dropped', () async {
      final prefs = ProfilePreferences.open(paths);
      final a = shot('retroarch', r'screenshots\a.png', start);
      final b = shot('retroarch', r'screenshots\b.png', start);
      final gone = p.join(paths.emulatorDir('retroarch'), 'screenshots', 'gone.png');
      await uploads(prefs, null).add('7', [gone, a, b]);
      var calls = 0;
      expect(await uploads(prefs, (_, _) async => throw StateError('offline ${calls++}')).sendWaiting(), 0);
      expect(uploads(prefs, null).waiting.map((s) => p.basename(s.path)), ['a.png', 'b.png']);
      final ok = <String>[];
      final q = uploads(prefs, (_, path) async {
        if (path == a) throw const ScreenshotRefused(400);
        ok.add(path);
      });
      expect(await q.sendWaiting(), 1);
      expect(ok, [b]);
      expect(q.waiting, isEmpty);
    });

    test('Upload screenshots off: nothing added, nothing sent', () async {
      final prefs = ProfilePreferences.open(paths);
      final q = uploads(prefs, (_, _) async => fail('sent while off'));
      expect(q.enabled, isTrue, reason: 'on by default');
      await q.setEnabled(false);
      await q.add('7', [shot('retroarch', r'screenshots\a.png', start)]);
      expect(q.waiting, isEmpty);
      expect(await q.sendWaiting(), 0);
    });
  });

  group('RomM', () {
    test('POST /api/screenshots with the rom id and the file; a 4xx is refused for good, a 5xx tried again', () async {
      final file = shot('retroarch', r'screenshots\a.png', start);
      var status = 200;
      final server = FakeDioAdapter((r) => (status: status, body: {'id': 1}));
      final romm = RommService(RomMConfig(baseUrl: 'http://romm', username: '', password: '', token: 't'))
        ..dio.httpClientAdapter = server;
      await romm.uploadScreenshot('7', file);
      final r = server.requests.single;
      expect(r.method, 'POST');
      expect(r.uri.path, '/api/screenshots');
      expect(r.uri.queryParameters['rom_id'], '7');
      status = 400;
      await expectLater(romm.uploadScreenshot('7', file), throwsA(isA<ScreenshotRefused>()));
      status = 503;
      await expectLater(romm.uploadScreenshot('7', file), throwsA(isNot(isA<ScreenshotRefused>())));
    });

    test("the player's own screenshots from RomM's game, kept in the snapshot", () {
      final game = Game.fromJson({
        ...gameJson(7, 'G'),
        'user_screenshots': [
          {'download_path': '/api/raw/assets/users/1/screenshots/a.png', 'missing_from_fs': false},
          {'download_path': '/api/raw/assets/users/1/screenshots/gone.png', 'missing_from_fs': true},
        ],
      });
      expect(game.userScreenshots, ['/api/raw/assets/users/1/screenshots/a.png']);
      expect(Game.fromJson(game.toJson()).userScreenshots, game.userScreenshots);
    });
  });
}
