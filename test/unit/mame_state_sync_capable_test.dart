// #62: MAME's save states through RomM, with no save sync.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategies/mame_strategy.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/core/save/save_sync_service.dart';
import 'package:gargosy/core/save/strategies/mame_save_strategy.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/emulators/emulator_layout.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import 'dart:io' as io;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

/// A state's start as MAME writes it (src/emu/save.cpp): magic, version,
/// flags, the system name.
Uint8List mameState({String magic = 'MAMESAVE', int version = 2, String system = 'sf2'}) {
  final b = Uint8List(64);
  b.setAll(0, magic.codeUnits);
  b[8] = version;
  b.setAll(0x0a, system.codeUnits);
  return b;
}

void main() {
  final game = Game.fromJson({...gameJson(1, 'Street Fighter II', fsName: 'sf2.zip'), 'platform_slug': 'arcade'});
  const rom = r'D:\roms\arcade\sf2.zip';

  group('in a profile', () {
    late AppRoot root;
    late ProfilePaths paths;
    setUp(() async {
      root = await tempAppRoot();
      paths = ProfilePaths(root, 'aaa');
    });
    tearDown(() => deleteTempDir(root.root));

    test("-state_directory <data>\\sta: the driver's own folder there is where states are read", () async {
      final dirs = ProfileSaveDirectories(root: root, paths: paths, prefs: MemoryPrefs());
      EmulatorLayout.of('mame').ensureFolders(dirs.dataDir('mame'));
      final exeDir = p.join(root.emulators, 'mame');
      io.Directory(exeDir).createSync(recursive: true);
      final args = await ProfileLaunchConfig.of('mame')!.prepare(
        LaunchContext(
          data: paths.emulatorDir('mame'),
          exeDir: exeDir,
          bios: root.bios,
          profileId: 'aaa',
          profilesDir: root.profiles,
          guard: PathGuard(root, activeProfileId: 'aaa'),
          roms: root.roms,
        ),
      );
      final told = args[args.indexOf('-state_directory') + 1];
      expect(await MameSaveStrategy(dirs).stateDirectory(game, rom), p.join(told, 'sf2'));
    });
  });

  test("outside a profile MAME's state folder isn't known: state sync skips it", () async {
    expect(() => MameSaveStrategy(DirectoryService(MemoryPrefs())).stateDirectory(game, rom), throwsStateError);
  });

  final s = MameSaveStrategy(DirectoryService(MemoryPrefs()));

  test("the matcher: any state name in the driver's folder; nothing else", () async {
    final match = (await s.stateFileMatcher(game, rom))!;
    for (final yes in ['1.sta', 'a.sta', 'auto.sta', 'boss_fight.sta']) {
      expect(match(yes), isTrue, reason: yes);
    }
    for (final no in ['1.sta.bak', '1.STA', 'sf2.nv', r'..\1.sta', 'sub/1.sta', '.sta']) {
      expect(match(no), isFalse, reason: no);
    }
  });

  test('slots: the key pressed (0-9), auto, else its name', () {
    expect(s.slotOf('1.sta'), const NumberedStateSlot(1));
    expect(s.slotOf('auto.sta'), const AutoStateSlot());
    expect(s.slotOf('a.sta'), const UnknownStateSlot('a.sta'));
  });

  test('a state starts MAMESAVE, format 2', () {
    expect(s.looksLikeValidState(mameState()), isTrue);
    expect(s.looksLikeValidState(mameState(version: 1)), isFalse);
    expect(s.looksLikeValidState(mameState(magic: 'NOTMAME!')), isFalse);
    expect(s.looksLikeValidState(Uint8List(4)), isFalse);
  });

  test(
    "the save pipeline is unchanged (it falls back to the platform's other strategy); states go through MAME's",
    () async {
      final prefs = MemoryPrefs();
      final dirs = DirectoryService(prefs);
      final sync = SaveSyncService(
        RommService(
          RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 'k'),
          skipConnectivityCheck: true,
        ),
        dirs,
        StrategyRegistry(dirs, prefs),
        prefs,
      );
      expect(sync.strategyForGame(game, emulatorId: 'mame'), isNot(isA<MameSaveStrategy>()));
      expect(sync.stateStrategyForGame(game, emulatorId: 'mame'), isA<MameSaveStrategy>());
      expect(
        sync.stateStrategyForGame(game, emulatorId: 'pcsx2'),
        same(sync.strategyForGame(game, emulatorId: 'pcsx2')),
        reason: 'an emulator with a save strategy keeps it for states',
      );
    },
  );

  test('Resume: -state <file>, which MAME takes as a full path', () {
    final emu = MAMEStrategy(DirectoryService(MemoryPrefs()));
    expect(emu.supportsStateSync, isTrue);
    expect(emu.supportsStateLoadOnLaunch, isTrue);
    expect(emu.stateLoadArgs(r'C:\d\sta\sf2\1.sta'), ['-state', r'C:\d\sta\sf2\1.sta']);
    expect(emu.canLoadState('1.sta'), isTrue);
  });
}
