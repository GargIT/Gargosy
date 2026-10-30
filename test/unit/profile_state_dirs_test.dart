// State-sync plan S0.2 (#58): for each emulator that syncs states, the folder
// the save code reads states from is exactly the one the emulator is told to
// write them to, in a profile. Compared as strings, so a match that only
// holds because Windows ignores case fails here.
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/storage/ini_file.dart';
import 'package:gargosy/core/save/strategies/dolphin_save_strategy.dart';
import 'package:gargosy/core/save/strategies/duckstation_save_strategy.dart';
import 'package:gargosy/core/save/strategies/mgba_save_strategy.dart';
import 'package:gargosy/core/save/strategies/pcsx2_save_strategy.dart';
import 'package:gargosy/core/save/strategies/ppsspp_save_strategy.dart';
import 'package:gargosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:gargosy/emulators/emulator_layout.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_secret_store.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late ProfilePaths paths;
  late ProfileSaveDirectories dirs;
  setUp(() async {
    root = await tempAppRoot();
    paths = ProfilePaths(root, 'aaa');
    dirs = ProfileSaveDirectories(root: root, paths: paths, prefs: MemoryPrefs());
  });
  tearDown(() => deleteTempDir(root.root));

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

  /// What the engine does before the first pull (PlayEngine.prepare).
  void firstRun(String emu) => EmulatorLayout.of(emu).ensureFolders(dirs.dataDir(emu));

  final psx = Game.fromJson({
    ...gameJson(1, 'Ape Escape', fsName: 'Ape Escape (USA).chd'),
    'platform_slug': 'psx',
    'title_id': 'SCUS-94423',
  });
  final ps2 = Game.fromJson({
    ...gameJson(2, 'Ico', fsName: 'Ico (USA).chd'),
    'platform_slug': 'ps2',
    'title_id': 'SCUS-97113',
  });
  final psxRom = r'D:\roms\psx\Ape Escape (USA).chd';

  group('DuckStation', () {
    DuckstationSaveStrategy strategy() => DuckstationSaveStrategy(dirs, dirs.prefs, platform: sandboxedPlatform(paths));

    test("a new profile, before DuckStation ever ran: the profile's own savestates folder", () async {
      firstRun('duckstation');
      expect(await strategy().stateDirectory(psx, psxRom), p.join(paths.emulatorDir('duckstation'), 'savestates'));
    });

    test('the folder DuckStation is told to write states to ([Folders] SaveStates) is where they are read', () async {
      firstRun('duckstation');
      final c = ctx('duckstation');
      final config = ProfileLaunchConfig.of('duckstation')!;
      await config.prepare(c);
      final told = IniFile(io.File(p.join(c.exeDir, 'settings.ini')).readAsStringSync()).get('Folders', 'SaveStates');
      expect(await strategy().stateDirectory(psx, psxRom), told, reason: 'during the session');
      await config.finish(c);
      expect(
        await strategy().stateDirectory(psx, psxRom),
        told,
        reason: 'after it, with settings.ini back in the profile',
      );
    });
  });

  group('PCSX2', () {
    test("-datapath <data>: PCSX2 writes states in <data>\\PCSX2\\sstates, which is where they're read", () async {
      firstRun('pcsx2');
      final args = await ProfileLaunchConfig.of('pcsx2')!.prepare(ctx('pcsx2'));
      final datapath = args[args.indexOf('-datapath') + 1];
      final strategy = Pcsx2SaveStrategy(dirs, dirs.prefs, platform: sandboxedPlatform(paths));
      // docs/emulator-profiles.md: PCSX2 adds a PCSX2\ level inside the data path.
      expect(await strategy.stateDirectory(ps2, r'D:\roms\ps2\Ico (USA).chd'), p.join(datapath, 'PCSX2', 'sstates'));
    });
  });

  group('PPSSPP (#59)', () {
    test(
      r"installed.txt makes <data> the memory stick: states in <data>\PSP\PPSSPP_STATE, where they're read",
      () async {
        firstRun('ppsspp');
        final c = ctx('ppsspp');
        await ProfileLaunchConfig.of('ppsspp')!.prepare(c);
        final stick = io.File(p.join(c.exeDir, 'installed.txt')).readAsStringSync().trim();
        final strategy = PpssppSaveStrategy(dirs, platform: sandboxedPlatform(paths));
        final psp = Game.fromJson({...gameJson(3, 'Daxter', fsName: 'Daxter (USA).iso'), 'platform_slug': 'psp'});
        expect(
          await strategy.stateDirectory(psp, r'D:\roms\psp\Daxter (USA).iso'),
          p.join(stick, 'PSP', 'PPSSPP_STATE'),
        );
      },
    );
  });

  group('Dolphin (#60)', () {
    test(r"--user=<data>: states in <data>\StateSaves, where they're read", () async {
      firstRun('dolphin');
      final args = await ProfileLaunchConfig.of('dolphin')!.prepare(ctx('dolphin'));
      final user = args.firstWhere((a) => a.startsWith('--user=')).substring('--user='.length);
      final strategy = DolphinSaveStrategy(dirs, platform: sandboxedPlatform(paths));
      final gc = Game.fromJson({...gameJson(4, 'Zelda', fsName: 'Zelda.rvz'), 'platform_slug': 'ngc'});
      expect(await strategy.stateDirectory(gc, r'D:\roms\ngc\Zelda.rvz'), p.join(user, 'StateSaves'));
    });
  });

  group('mGBA (#61)', () {
    test("-C savestatePath=<data>\\states: where they're read", () async {
      firstRun('mgba');
      final args = await ProfileLaunchConfig.of('mgba')!.prepare(ctx('mgba'));
      final told = args.firstWhere((a) => a.startsWith('savestatePath=')).substring('savestatePath='.length);
      final strategy = MgbaSaveStrategy(dirs, platform: sandboxedPlatform(paths));
      final gba = Game.fromJson({...gameJson(5, 'Metroid', fsName: 'Metroid.gba'), 'platform_slug': 'gba'});
      expect(await strategy.stateDirectory(gba, r'D:\roms\gba\Metroid.gba'), told);
    });
  });

  group('RetroArch', () {
    RetroArchSaveStrategy strategy() =>
        RetroArchSaveStrategy(dirs, prefs: dirs.prefs, platform: sandboxedPlatform(paths));
    String cfgPath() => p.join(paths.emulatorDir('retroarch'), 'retroarch.cfg');
    String? key(String name) =>
        RegExp('^$name\\s*=\\s*"([^"]*)"', multiLine: true).firstMatch(io.File(cfgPath()).readAsStringSync())?.group(1);

    test('a new profile: states sorted by core, under savestate_directory, as RetroArch writes them', () async {
      firstRun('retroarch');
      await ProfileLaunchConfig.of('retroarch')!.prepare(ctx('retroarch'));
      // Pinned before RetroArch's first exit writes its own default.
      expect(key('sort_savestates_enable'), 'true');
      expect(key('sort_savestates_by_content_enable'), 'false');
      final dir = await strategy().stateDirectory(psx, psxRom);
      expect(p.dirname(dir), key('savestate_directory'));
      expect(p.basename(dir), isNotEmpty, reason: "the core's own folder");
    });

    test("the player's own sorting choice in the profile is kept, and the save code follows it", () async {
      firstRun('retroarch');
      io.File(cfgPath())
        ..createSync(recursive: true)
        ..writeAsStringSync('sort_savestates_enable = "false"\n');
      await ProfileLaunchConfig.of('retroarch')!.prepare(ctx('retroarch'));
      expect(key('sort_savestates_enable'), 'false');
      expect(await strategy().stateDirectory(psx, psxRom), key('savestate_directory'));
    });
  });

  group('a profile that never ran the emulator', () {
    test("listing states makes an installed emulator's folders first, as its launch would", () async {
      final launch = ProfileLaunchDirectories(
        secrets: FakeSecretStore(),
        root: root,
        paths: paths,
        prefs: MemoryPrefs(),
      );
      final strategy = Pcsx2SaveStrategy(dirs, dirs.prefs, platform: sandboxedPlatform(paths));
      await expectLater(strategy.stateDirectory(ps2, r'D:\roms\ps2\Ico (USA).chd'), throwsException);

      await launch.ensureDataFolders('pcsx2', 'pcsx2-qt.exe');
      expect(io.Directory(dirs.dataDir('pcsx2')).existsSync(), isFalse, reason: 'not installed: nothing made');

      io.File(p.join(root.emulators, 'pcsx2', 'pcsx2-qt.exe'))
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      await launch.ensureDataFolders('pcsx2', 'pcsx2-qt.exe');
      expect(
        await strategy.stateDirectory(ps2, r'D:\roms\ps2\Ico (USA).chd'),
        p.join(dirs.dataDir('pcsx2'), 'PCSX2', 'sstates'),
      );
    });
  });
}
