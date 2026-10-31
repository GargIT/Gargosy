// Issue #7: RetroArch's saves through sigil, per game core.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/providers/retry.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/state_sync_capable.dart';
import 'package:gargosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/engine_providers.dart';
import 'package:gargosy/sigil/sigil_save_strategy.dart';
import 'package:gargosy/sigil/sigil_state_store.dart';
import 'package:gargosy/sigil/sigil_sync.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import 'save_sync_regression_test.mocks.dart';

Uint8List pattern(int seed, int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (seed * 31 + i) & 0xFF]);

void main() {
  late io.Directory tmp;
  late String dataDir;
  late RetroArchSaveStrategy base;
  late List<SigilSyncCall> collected;

  setUp(() {
    tmp = io.Directory.systemTemp.createTempSync('gargosy-ra-sigil-');
    dataDir = p.join(tmp.path, 'profiles', 'p1', 'emulators', 'retroarch');
    final dirs = MockDirectoryService();
    when(dirs.findEmulatorExecutable(argThat(isA<String>()), argThat(isA<String>()))).thenAnswer((_) async => null);
    when(dirs.linuxSyncPreset).thenReturn('default');
    base = RetroArchSaveStrategy(dirs, platform: PlatformInfo('windows', environment: {'APPDATA': tmp.path}));
    collected = [];
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Game game(String slug, String rom, {String? titleId}) =>
      Game(id: '7', name: rom, fsName: rom, platformSlug: slug, fileSize: 0, titleId: titleId);

  /// The wrapper, with sigil itself ([real]) or a collect that records the call.
  SigilSaveStrategy wrapper({bool real = false}) => SigilSaveStrategy.forEmulator(
    'retroarch',
    base: base,
    emulatorDir: () => dataDir,
    states: SigilStateStore(p.join(tmp.path, 'sigil')),
    unitsDir: p.join(tmp.path, 'sigil', 'units'),
    collect: real
        ? null
        : (call) async {
            collected.add(call);
            return const SigilCollected(
              artifact: '',
              data: null,
              contentHash: '',
              identityHash: '',
              changed: false,
              state: null,
              holding: null,
              unowned: [],
              restoreAgain: false,
            );
          },
    identify: (path, {platform}) async => null,
  )!;

  group('the layout is the game\'s core', () {
    test('the platform\'s default core (Game Boy: gambatte), saves\\ as the root', () async {
      await wrapper().getSaveFiles(game('gb', 'Tetris.gb'), p.join(tmp.path, 'Tetris.gb'));
      expect(collected.single.layout, base.coreIdFor(game('gb', 'Tetris.gb')));
      expect(collected.single.platform, 'gb');
      expect(collected.single.saveRoot, p.join(dataDir, 'saves'));
    });

    test("the platform's chosen core (Settings)", () async {
      base.loadCoreOverrides({'psx': 'pcsx_rearmed_libretro'});
      await wrapper().getSaveFiles(game('psx', 'FF7.chd', titleId: 'SLUS-00594'), p.join(tmp.path, 'FF7.chd'));
      expect(collected.single.layout, 'pcsx_rearmed');
    });

    test('the core the game was launched with wins (the core picker)', () async {
      base.loadCoreOverrides({'psx': 'pcsx_rearmed_libretro'});
      base.setLaunchCoreOverride('swanstation_libretro');
      await wrapper().getSaveFiles(game('psx', 'FF7.chd', titleId: 'SLUS-00594'), p.join(tmp.path, 'FF7.chd'));
      expect(collected.single.layout, 'swanstation');
    });

    test('LRPS2: layout pcsx2, shared cards (the default) in system\\pcsx2\\memcards', () async {
      io.File(p.join(dataDir, 'config', 'retroarch-core-options.cfg'))
        ..createSync(recursive: true)
        ..writeAsStringSync('other_core_key = "x"\n');
      base.loadCoreOverrides({'ps2': 'pcsx2_libretro'});
      await wrapper().getSaveFiles(game('ps2', 'Game A.chd', titleId: 'SLUS-20328'), p.join(tmp.path, 'Game A.chd'));
      expect(collected.single.layout, 'pcsx2');
      expect(collected.single.saveRoot, p.join(dataDir, 'system', 'pcsx2', 'memcards'));
      expect(collected.single.options['other_core_key'], 'x');
    });

    test("LRPS2 with Shared Memory Cards off in the core's own .opt: the game's card in saves\\", () async {
      io.File(p.join(dataDir, 'config', 'retroarch-core-options.cfg'))
        ..createSync(recursive: true)
        ..writeAsStringSync('pcsx2_shared_memory_cards = "enabled"\n');
      io.File(p.join(dataDir, 'config', 'LRPS2', 'LRPS2.opt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('pcsx2_shared_memory_cards = "disabled"\n');
      base.loadCoreOverrides({'ps2': 'pcsx2_libretro'});
      await wrapper().getSaveFiles(game('ps2', 'Game A.chd', titleId: 'SLUS-20328'), p.join(tmp.path, 'Game A.chd'));
      expect(collected.single.options['pcsx2_shared_memory_cards'], 'disabled');
      expect(collected.single.saveRoot, p.join(dataDir, 'saves'));
    });

    test("a game's own .opt wins over the core's", () async {
      io.File(p.join(dataDir, 'config', 'LRPS2', 'LRPS2.opt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('pcsx2_shared_memory_cards = "disabled"\n');
      io.File(p.join(dataDir, 'config', 'LRPS2', 'Game A.opt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('pcsx2_shared_memory_cards = "enabled"\n');
      base.loadCoreOverrides({'ps2': 'pcsx2_libretro'});
      await wrapper().getSaveFiles(game('ps2', 'Game A.chd', titleId: 'SLUS-20328'), p.join(tmp.path, 'Game A.chd'));
      expect(collected.single.saveRoot, p.join(dataDir, 'system', 'pcsx2', 'memcards'));
    });
  });

  group('what stays with RetroArch\'s own strategy', () {
    for (final slug in ['snes', 'gba', 'genesis', 'nes', 'nds', 'arcade', 'dc']) {
      test('$slug: not sigil\'s (sigil refuses its saves, or it is not checked yet)', () async {
        final w = wrapper();
        final g = game(slug, 'Game.bin');
        expect(w.uploadSlotFor(g), base.uploadSlotFor(g));
        expect(w.restoresUnitsItselfFor(g), base.restoresUnitsItselfFor(g));
        expect(await w.saveSyncBlockedReason(g, 'x'), await base.saveSyncBlockedReason(g, 'x'));
        expect(collected, isEmpty);
      });
    }

    test('save states: the wrapper is still StateSyncCapable, through RetroArch\'s strategy', () async {
      final w = wrapper();
      expect(w, isA<StateSyncCapable>());
      expect((w as StateSyncCapable).slotOf('Tetris.state1'), base.slotOf('Tetris.state1'));
      // Resume starts the core the state belongs to: the wrapper must say it.
      final g = game('psx', 'WipEout (Europe).chd');
      expect((w as StateSyncCapable).stateCoreFor(g), isNotNull);
      expect((w as StateSyncCapable).stateCoreFor(g), base.stateCoreFor(g));
      expect((w as StateSyncCapable).stateLabelFor(g), base.stateLabelFor(g));
      expect((w as StateSyncCapable).stateLabels, base.stateLabels);
    });

    test('code that asks for RetroArch\'s strategy finds it under the wrapper', () {
      final w = wrapper();
      expect(w.wrapped, same(base));
      expect(w.unwrapped, same(base));
      expect(base.unwrapped, same(base));
    });
  });

  group('through sigil, on real files', () {
    test('push: <stem>.srm becomes one unit for the autosave slot', () async {
      io.File(p.join(dataDir, 'saves', 'Tetris (World).srm'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(pattern(1, 8192));
      final g = game('gb', 'Tetris (World).gb');
      final w = wrapper(real: true);
      expect(w.uploadSlotFor(g), 'autosave');
      final files = await w.getSaveFiles(g, p.join(tmp.path, 'roms', 'gb', 'Tetris (World).gb'));
      expect(files.map((f) => p.basename(f.path)), ['Tetris (World).srm']);
      expect(files.single.readAsBytesSync(), pattern(1, 8192));
      expect(p.isWithin(p.join(tmp.path, 'sigil', 'units'), files.single.path), isTrue, reason: 'never in saves\\');
    });

    test('pull: the unit goes back into saves\\ under RetroArch\'s name', () async {
      final g = game('gb', 'Tetris (World).gb');
      final ok = await wrapper(real: true)
          .restoreSave(g, p.join(tmp.path, 'roms', 'gb', 'Tetris (World).gb'), pattern(2, 8192), 'Tetris (World).srm');
      expect(ok, isTrue);
      expect(io.File(p.join(dataDir, 'saves', 'Tetris (World).srm')).readAsBytesSync(), pattern(2, 8192));
    });
  });

  test('a profile: RetroArch\'s save strategy is sigil\'s wrapper around RetroArchSaveStrategy', () async {
    final root = await tempAppRoot();
    addTearDown(() => deleteTempDir(root.root));
    final c = ProviderContainer(
      retry: noRetry,
      overrides: [appRootProvider.overrideWithValue(root), appPreferencesProvider.overrideWithValue(MemoryPrefs())],
    );
    addTearDown(c.dispose);
    final anna = await c
        .read(profileStoreProvider)
        .create(name: 'Anna', colorIndex: 0, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna');
    await c.read(activeProfileProvider.notifier).activate(anna, const ProfileLogin(token: 't', kind: 'device'));
    final sync = c.read(saveSyncServiceProvider)!;
    final s = sync.getStrategyForGame(gameFixture('gb'), emulatorId: 'retroarch');
    expect(s, isA<SigilSaveStrategy>());
    expect(s!.unwrapped, isA<RetroArchSaveStrategy>());
    expect(
      await s.getSaveDir(gameFixture('gb'), p.join(root.roms, 'gb', 'G.gb')),
      p.join(ProfilePaths(root, anna.id).emulatorDir('retroarch'), 'saves'),
    );
    c.read(activeProfileProvider.notifier).signOut();
    await Future<void>.delayed(const Duration(milliseconds: 300)); // the backups box closes
  });
}

Game gameFixture(String slug) => game(1, 'G', platform: slug);
