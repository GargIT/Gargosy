import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/dolphin_save_strategy.dart';
import 'package:gargosy/core/save/strategies/duckstation_save_strategy.dart';
import 'package:gargosy/core/save/strategies/mgba_save_strategy.dart';
import 'package:gargosy/core/save/strategies/pcsx2_save_strategy.dart';
import 'package:gargosy/core/save/strategies/ppsspp_save_strategy.dart';
import 'package:gargosy/core/save/strategies/xenia_save_strategy.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_secret_store.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  setUp(() async => root = await tempAppRoot());
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  ProfileSaveDirectories dirs(String id) =>
      ProfileSaveDirectories(root: root, paths: ProfilePaths(root, id), prefs: MemoryPrefs());

  /// The layout each emulator writes in a profile (docs/emulator-profiles.md).
  void layout(String profile) {
    final e = ProfilePaths(root, profile).emulatorsDir;
    for (final d in [
      r'dolphin\GC',
      r'dolphin\Wii',
      r'pcsx2\PCSX2\memcards',
      r'duckstation\memcards',
      r'ppsspp\PSP\SAVEDATA',
      r'xenia_canary\content',
      r'mgba\saves',
    ]) {
      io.Directory(p.join(e, d)).createSync(recursive: true);
    }
    io.File(p.join(e, 'duckstation', 'settings.ini'))
        .writeAsStringSync('[MemoryCards]\nDirectory = ${p.join(e, 'duckstation', 'memcards')}\n');
  }

  test('dataDir is the profile\'s own folder for an emulator', () {
    expect(dirs('aaa').dataDir('pcsx2'), p.join(root.profiles, 'aaa', 'emulators', 'pcsx2'));
  });

  test('two profiles resolve different save folders for every emulator', () async {
    layout('aaa');
    layout('bbb');
    final game = Game.fromJson({...gameJson(1, 'G', platform: 'ps2'), 'title_id': 'SLUS-21050'});
    Future<List<String?>> folders(String profile) async {
      final d = dirs(profile);
      final platform = sandboxedPlatform(ProfilePaths(root, profile));
      return [
        // Dolphin's GameCube saves are sigil's (#57): its states' folder.
        await DolphinSaveStrategy(d, platform: platform).stateDirectory(game, r'C:\roms\gc\g.iso'),
        // PCSX2's cards are sigil's (#57): its own folder is the states'.
        await Pcsx2SaveStrategy(d, d.prefs, platform: platform).stateDirectory(game, r'C:\roms\ps2\g.chd'),
        // DuckStation's cards are sigil's (#57): its own folder is the states'.
        await DuckstationSaveStrategy(d, d.prefs, platform: platform).stateDirectory(game, r'C:\roms\psx\g.chd'),
        // PPSSPP's saves are sigil's (#57): its own folder is the states'.
        await PpssppSaveStrategy(d, platform: platform).stateDirectory(game, r'C:\roms\psp\g.iso'),
        await XeniaSaveStrategy(d, platform: platform).getSaveDir(
          Game.fromJson({...gameJson(2, 'x', platform: 'xbox360'), 'title_id': '4D5307E6'}),
          r'C:\roms\x\g.iso',
        ),
        await MgbaSaveStrategy(d, platform: platform).getSaveDir(game, p.join(root.roms, 'gba', 'g.gba')),
      ];
    }

    final a = await folders('aaa');
    final b = await folders('bbb');
    for (var i = 0; i < a.length; i++) {
      expect(a[i], isNotNull, reason: 'strategy $i found nothing');
      expect(p.isWithin(ProfilePaths(root, 'aaa').emulatorsDir, a[i]!), isTrue, reason: 'strategy $i: ${a[i]}');
      expect(p.isWithin(ProfilePaths(root, 'bbb').emulatorsDir, b[i]!), isTrue, reason: 'strategy $i: ${b[i]}');
      expect(a[i], isNot(b[i]));
    }
  });

  test('fallbacks stay in the profile', () {
    final platform = sandboxedPlatform(ProfilePaths(root, 'aaa'));
    final e = ProfilePaths(root, 'aaa').emulatorsDir;
    expect(platform.environment['APPDATA'], e);
    expect(platform.environment['LOCALAPPDATA'], e);
    expect(p.isWithin(e, platform.environment['USERPROFILE']!), isTrue);
    expect(platform.isWindows, isTrue);
  });

  test('mGBA saves go to the profile, never next to the ROM', () async {
    final rom = io.File(p.join(root.roms, 'gba', 'g.gba'))..createSync(recursive: true);
    io.File(p.join(root.roms, 'gba', 'g.sav')).writeAsStringSync('old save next to the rom');
    final d = dirs('aaa');
    final dir = await MgbaSaveStrategy(
      d,
      platform: sandboxedPlatform(ProfilePaths(root, 'aaa')),
    ).getSaveDir(game(1, 'g'), rom.path);
    expect(dir, p.join(d.dataDir('mgba'), 'saves'));
  });

  test('an emulator\'s app-support name maps to its profile folder', () async {
    final d = dirs('aaa');
    expect(await d.getEmulatorAppSupportDirectory('DuckStation'), d.dataDir('duckstation'));
    expect(await d.getEmulatorAppSupportDirectory('pcsx2'), p.join(d.dataDir('pcsx2'), 'PCSX2'));
    expect(await d.getEmulatorSystemDirectory('pcsx2'), root.bios);
    expect(await d.getEmulatorDirectory('temp'), p.join(root.appData, 'temp'));
  });

  test('the launch view finds the real exe under emulators\\<id>', () async {
    final exe = io.File(p.join(root.emulators, 'dolphin', 'Dolphin-x64', 'Dolphin.exe'))..createSync(recursive: true);
    final l = ProfileLaunchDirectories(
      secrets: FakeSecretStore(),
      root: root,
      paths: ProfilePaths(root, 'aaa'),
      prefs: MemoryPrefs(),
    );
    expect(await l.findEmulatorExecutable('dolphin', 'Dolphin.exe'), exe.path);
    expect(await l.findEmulatorExecutable('pcsx2', 'pcsx2-qt.exe'), isNull);
  });

  test("RetroArch's system folder is the profile's own; other emulators read the shared BIOS", () async {
    final d = dirs('aaa');
    expect(await d.getEmulatorSystemDirectory('retroarch'), p.join(d.dataDir('retroarch'), 'system'));
    expect(await d.getEmulatorSystemDirectory('duckstation'), root.bios);
  });

  test('repoint before a pull rewrites the profile config, also with no install yet', () async {
    final l = ProfileLaunchDirectories(
      secrets: FakeSecretStore(),
      root: root,
      paths: ProfilePaths(root, 'aaa'),
      prefs: MemoryPrefs(),
    );
    final ini = io.File(p.join(l.dataDir('duckstation'), 'settings.ini'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[MemoryCards]\nDirectory = E:\\Old\\memcards\n');
    l.repoint('duckstation');
    expect(ini.readAsStringSync(), contains(p.join(l.dataDir('duckstation'), 'memcards')));
    l.repoint('nothing-known'); // no config: nothing to do
  });

  test("an emulator's game folders are the roms folders of the platforms it plays that exist", () {
    for (final d in ['ps2', 'psx', 'snes']) {
      io.Directory(p.join(root.roms, d)).createSync(recursive: true);
    }
    final l = ProfileLaunchDirectories(
      secrets: FakeSecretStore(),
      root: root,
      paths: ProfilePaths(root, 'aaa'),
      prefs: MemoryPrefs(),
    );
    expect(l.gameFoldersFor('pcsx2'), [p.join(root.roms, 'ps2')]);
    expect(l.gameFoldersFor('duckstation'), [p.join(root.roms, 'psx')]);
    expect(l.gameFoldersFor('dolphin'), isEmpty);
  });
}
