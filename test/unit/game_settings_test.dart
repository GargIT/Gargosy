import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/storage/ini_file.dart';
import 'package:gargosy/emulators/game_settings.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_secret_store.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  test('extra arguments split at spaces, a quoted part kept whole', () {
    expect(splitArgs(''), isEmpty);
    expect(splitArgs('  --verbose   -x 2 '), ['--verbose', '-x', '2']);
    expect(splitArgs('--set "a b" c'), ['--set', 'a b', 'c']);
    expect(splitArgs('""'), ['']);
  });

  group('kept per game and emulator in the profile', () {
    test('written, read, cleared when empty, reset for every emulator', () async {
      final prefs = MemoryPrefs();
      final store = GameSettingsStore(prefs);
      expect(store.read('7', 'pcsx2').isEmpty, isTrue);
      await store.write('7', 'pcsx2', const GameSettings(widescreen: Widescreen.on, args: '-fastboot'));
      await store.write('7', 'retroarch', const GameSettings(shader: 'crt/crt-royale.slangp'));
      expect(store.read('7', 'pcsx2').widescreen, Widescreen.on);
      expect(store.read('7', 'pcsx2').args, '-fastboot');
      expect(store.read('7', 'retroarch').shader, 'crt/crt-royale.slangp');
      expect(store.read('8', 'pcsx2').isEmpty, isTrue, reason: 'another game has none');
      await store.write('7', 'pcsx2', GameSettings.none);
      expect(store.read('7', 'retroarch').shader, isNotNull);
      await store.reset('7');
      expect(prefs.getString(GameSettingsStore.key('7')), isNull);
    });

    test('a shader outside the shaders folder is never read back', () {
      expect(GameSettings.fromJson({'shader': r'C:\evil.slangp'}).shader, isNull);
      expect(GameSettings.fromJson({'shader': r'..\..\x.slangp'}).shader, isNull);
      expect(GameSettings.fromJson({'shader': 'crt/x.slangp'}).shader, 'crt/x.slangp');
    });
  });

  group('the arguments each emulator gets', () {
    test("RetroArch: --set-shader from its shaders folder; another emulator never gets it", () {
      const s = GameSettings(shader: r'crt\crt-geom.slangp', args: '--verbose');
      expect(gameSettingArgs('retroarch', s, r'C:\G\emulators\retroarch'), [
        '--set-shader',
        r'C:\G\emulators\retroarch\shaders\crt\crt-geom.slangp',
        '--verbose',
      ]);
      expect(gameSettingArgs('pcsx2', s, r'C:\x'), ['--verbose']);
    });

    test('Dolphin and Flycast: widescreen for this launch only; left to the emulator, nothing', () {
      expect(gameSettingArgs('dolphin', const GameSettings(widescreen: Widescreen.on), ''), [
        '-C',
        'GFX.Settings.wideScreenHack=True',
      ]);
      expect(gameSettingArgs('flycast', const GameSettings(widescreen: Widescreen.off), ''), [
        '-config',
        'config:rend.WideScreen=no',
      ]);
      expect(gameSettingArgs('dolphin', GameSettings.none, ''), isEmpty);
    });
  });

  group("PCSX2's and DuckStation's own settings", () {
    late AppRoot root;
    late PathGuard guard;
    late String data;
    late String exeDir;
    setUp(() async {
      root = await tempAppRoot();
      guard = PathGuard(root, activeProfileId: 'aaa');
      data = ProfilePaths(root, 'aaa').emulatorDir('pcsx2');
      exeDir = p.join(root.emulators, 'pcsx2');
    });
    tearDown(() => deleteTempDir(root.root));

    String ini() => p.join(data, 'PCSX2', 'inis', 'PCSX2.ini');

    test("PCSX2: on for the game, the player's own value back for a game that leaves it", () {
      io.File(ini())
        ..createSync(recursive: true)
        ..writeAsStringSync('[EmuCore]\nEnableWideScreenPatches = false\n');
      applyGameSettingKeys('pcsx2', const GameSettings(widescreen: Widescreen.on), data, exeDir, guard);
      expect(IniFile(io.File(ini()).readAsStringSync()).get('EmuCore', 'EnableWideScreenPatches'), 'true');
      // A second game with it off keeps the first original.
      applyGameSettingKeys('pcsx2', const GameSettings(widescreen: Widescreen.off), data, exeDir, guard);
      applyGameSettingKeys('pcsx2', GameSettings.none, data, exeDir, guard);
      expect(IniFile(io.File(ini()).readAsStringSync()).get('EmuCore', 'EnableWideScreenPatches'), 'false');
      expect(io.File(p.join(data, '.gargosy-game-settings.json')).existsSync(), isFalse);
    });

    test('DuckStation: the swapped settings.ini gets both keys; a key it never had is taken out again', () {
      final duck = ProfilePaths(root, 'aaa').emulatorDir('duckstation');
      final live = p.join(root.emulators, 'duckstation', 'settings.ini');
      io.File(live)
        ..createSync(recursive: true)
        ..writeAsStringSync('[Display]\nAspectRatio = Auto (Game Native)\n');
      applyGameSettingKeys('duckstation', const GameSettings(widescreen: Widescreen.on), duck, p.dirname(live), guard);
      var settings = IniFile(io.File(live).readAsStringSync());
      expect(settings.get('GPU', 'WidescreenHack'), 'true');
      expect(settings.get('Display', 'AspectRatio'), '16:9');
      applyGameSettingKeys('duckstation', GameSettings.none, duck, p.dirname(live), guard);
      settings = IniFile(io.File(live).readAsStringSync());
      expect(settings.get('GPU', 'WidescreenHack'), isNull);
      expect(settings.get('Display', 'AspectRatio'), 'Auto (Game Native)');
    });

    test('nothing set and nothing kept: the file is left as it is', () {
      applyGameSettingKeys('pcsx2', GameSettings.none, data, exeDir, guard);
      expect(io.File(ini()).existsSync(), isFalse);
    });
  });

  test("a launch: the game's arguments after the profile's, before the strategy's and the ROM", () async {
    final root = await tempAppRoot();
    addTearDown(() => deleteTempDir(root.root));
    final paths = ProfilePaths(root, 'aaa');
    final exe = io.File(p.join(root.emulators, 'dolphin', 'Dolphin.exe'))..createSync(recursive: true);
    final prefs = MemoryPrefs();
    await GameSettingsStore(prefs)
        .write('1', 'dolphin', const GameSettings(widescreen: Widescreen.on, args: '--debugger'));
    final started = <List<String>>[];
    final dirs = ProfileLaunchDirectories(
      secrets: FakeSecretStore(),
      root: root,
      paths: paths,
      prefs: prefs,
      start: (exePath, args, {workingDirectory, environment}) async {
        started.add([exePath, ...args]);
        return io.Process.start('cmd.exe', ['/c', 'exit', '0']);
      },
    );
    await dirs.launchGameWithHandle(game(1, 'G'), r'D:\roms\gc\g.iso', 'dolphin', exe.path, args: ['-b', '-e']);
    await dirs.launchGameWithHandle(game(2, 'H'), r'D:\roms\gc\h.iso', 'dolphin', exe.path, args: ['-b', '-e']);
    expect(started.first, [
      exe.path,
      '-C',
      'Dolphin.Display.Fullscreen=True',
      '--user=${paths.emulatorDir('dolphin')}',
      '-C',
      'GFX.Settings.wideScreenHack=True',
      '--debugger',
      '-b',
      '-e',
      r'D:\roms\gc\g.iso',
    ]);
    expect(started.last, isNot(contains('--debugger')), reason: 'that game only');
  });
}
