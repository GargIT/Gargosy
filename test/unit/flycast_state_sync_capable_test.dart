// #63: Flycast's save states through RomM; its saves stay with sigil.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategies/flycast_strategy.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/core/save/save_state_info.dart';
import 'package:gargosy/core/save/save_sync_service.dart';
import 'package:gargosy/core/save/strategies/flycast_save_strategy.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/emulators/emulator_layout.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/without_sigil.dart';

/// A state as Flycast writes it (core/nullDC.cpp): the header, the PNG, the data.
Uint8List flycastState({List<int> png = const [0x89, 0x50, 0x4E, 0x47], int version = 850}) {
  final b = Uint8List(24 + png.length + 100);
  final d = ByteData.sublistView(b);
  b.setAll(0, 'FLYSAVE1'.codeUnits);
  d.setUint64(8, 1760000000, Endian.little);
  d.setUint32(16, version, Endian.little);
  d.setUint32(20, png.length, Endian.little);
  b.setAll(24, png);
  return b;
}

void main() {
  final game = Game.fromJson({...gameJson(1, 'Crazy Taxi', fsName: 'Crazy Taxi (USA).chd'), 'platform_slug': 'dc'});
  const rom = r'D:\roms\dc\Crazy Taxi (USA).chd';
  final s = FlycastSaveStrategy(DirectoryService(MemoryPrefs()));

  test("the matcher: the content's stem, slot 0 bare and 1-99 numbered; not Flycast's scratch files", () async {
    final match = (await s.stateFileMatcher(game, rom))!;
    for (final yes in [
      'Crazy Taxi (USA).state',
      'Crazy Taxi (USA)_1.state',
      'Crazy Taxi (USA)_42.state',
      'crazy taxi (usa)_2.state',
    ]) {
      expect(match(yes), isTrue, reason: yes);
    }
    for (final no in [
      'Crazy Taxi (USA).state.net',
      'Crazy Taxi (USA).state.tmp',
      'Crazy Taxi (USA)_100.state',
      'Crazy Taxi 2 (USA).state',
      'Crazy Taxi (USA).state.bak',
      r'..\Crazy Taxi (USA).state',
    ]) {
      expect(match(no), isFalse, reason: no);
    }
  });

  test('slots: none is 0, else the number', () {
    expect(s.slotOf('Crazy Taxi (USA).state'), const NumberedStateSlot(0));
    expect(s.slotOf('Crazy Taxi (USA)_3.state'), const NumberedStateSlot(3));
    expect(s.slotOf('x.vmu'), isA<UnknownStateSlot>());
  });

  test("another slot's state name (#92): _N.state, slot 0 .state", () {
    expect(s.stateFileForSlot('Crazy Taxi (USA).state', 2), 'Crazy Taxi (USA)_2.state');
    expect(s.stateFileForSlot('Crazy Taxi (USA)_3.state', 0), 'Crazy Taxi (USA).state');
    expect(s.stateFileForSlot('x.vmu', 1), isNull);
  });

  test('a state has the FLYSAVE1 header, or is an older one without it', () {
    expect(s.looksLikeValidState(flycastState()), isTrue);
    expect(s.looksLikeValidState(Uint8List(2048)), isTrue, reason: 'a state from before the header');
    expect(s.looksLikeValidState(Uint8List(100)), isFalse);
  });

  group('on disk', () {
    late io.Directory tmp;
    setUp(() => tmp = io.Directory.systemTemp.createTempSync('gargosy-flycaststate-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('the PNG after the header is the screenshot; the format version is recorded', () async {
      final state = io.File(p.join(tmp.path, 'a.state'))
        ..writeAsBytesSync(flycastState(png: [0x89, 0x50, 0x4E, 0x47, 9, 9]));
      expect(await s.stateScreenshot(state), [0x89, 0x50, 0x4E, 0x47, 9, 9]);
      expect((await s.describeState(state)).formatId, '850');
    });

    test('an older state: no screenshot, no format, no throw', () async {
      final state = io.File(p.join(tmp.path, 'a.state'))..writeAsBytesSync(Uint8List(2048));
      expect(await s.stateScreenshot(state), isNull);
      expect((await s.describeState(state)).formatId, isNull);
    });
  });

  test("in a profile: the states folder Flycast is told (Dreamcast.SavestatePath) is where they're read", () async {
    final root = await tempAppRoot();
    addTearDown(() => deleteTempDir(root.root));
    final paths = ProfilePaths(root, 'aaa');
    final dirs = ProfileSaveDirectories(root: root, paths: paths, prefs: MemoryPrefs());
    EmulatorLayout.of('flycast').ensureFolders(dirs.dataDir('flycast'));
    final exeDir = p.join(root.emulators, 'flycast');
    io.Directory(exeDir).createSync(recursive: true);
    final args = await ProfileLaunchConfig.of('flycast')!.prepare(
      LaunchContext(
        data: paths.emulatorDir('flycast'),
        exeDir: exeDir,
        bios: root.bios,
        profileId: 'aaa',
        profilesDir: root.profiles,
        guard: PathGuard(root, activeProfileId: 'aaa'),
        roms: root.roms,
      ),
    );
    final told = RegExp(r'config:Dreamcast\.SavestatePath=([^,]+)').firstMatch(args.join(' '))!.group(1);
    expect(await FlycastSaveStrategy(dirs).stateDirectory(game, rom), told);
  });

  test("saves stay with sigil's wrapper; states go through Flycast's state strategy", () {
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
      wrapSaves: withoutSigil,
    );
    expect(sync.strategyForGame(game, emulatorId: 'flycast'), isNot(isA<FlycastSaveStrategy>()));
    expect(sync.stateStrategyForGame(game, emulatorId: 'flycast'), isA<FlycastSaveStrategy>());
  });

  group('Resume', () {
    final emu = FlycastStrategy(DirectoryService(MemoryPrefs()));

    test("the state's slot loads at boot, for this launch only", () {
      expect(emu.supportsStateSync, isTrue);
      expect(emu.supportsStateLoadOnLaunch, isTrue);
      expect(emu.stateLoadArgs(r'C:\d\states\Crazy Taxi (USA)_3.state'), [
        '-config',
        'config:Dreamcast.AutoLoadState=yes,config:Dreamcast.SavestateSlot=3',
      ]);
      expect(emu.stateLoadArgs(r'C:\d\states\Crazy Taxi (USA).state'), [
        '-config',
        'config:Dreamcast.AutoLoadState=yes,config:Dreamcast.SavestateSlot=0',
      ]);
    });

    test('only a slot state can be loaded', () {
      expect(emu.canLoadState('Crazy Taxi (USA)_3.state'), isTrue);
      expect(emu.canLoadState('Crazy Taxi (USA).state.net'), isFalse);
    });
  });
}
