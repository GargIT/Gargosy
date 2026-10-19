// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/ps2_save_folders.dart';
import 'package:gargosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;

import 'save_sync_regression_test.mocks.dart';

/// RetroArch's PS2 core, LRPS2, keeps every game's saves on shared memory
/// cards in the system folder. sigil syncs them (#57); what's left here is
/// whether they can be synced (the serial tells this game's saves from the
/// others') and whether a pull must finish before launch.
void main() {
  late Directory tempDir;
  late String raDir;
  late String memcards;
  late RetroArchSaveStrategy strategy;
  String? serial;

  final game = Game(id: '77', name: 'Ace Combat 5', fsName: 'Ace Combat 5 (USA).chd', platformSlug: 'ps2', fileSize: 0);
  late String romPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ra_lrps2_');
    raDir = p.join(tempDir.path, 'RetroArch');
    memcards = p.join(raDir, 'system', 'pcsx2', 'memcards');
    await Directory(memcards).create(recursive: true);
    await Directory(p.join(raDir, 'saves')).create(recursive: true);
    await File(p.join(raDir, 'retroarch.cfg')).writeAsString(
      [
        'savefile_directory = "${p.join(raDir, 'saves')}"',
        'system_directory = ":\\system"',
        'sort_savefiles_enable = "true"',
      ].join('\n'),
    );
    romPath = p.join(tempDir.path, 'roms', 'ps2', 'Ace Combat 5 (USA).chd');
    serial = 'SLUS-20851';

    final dirService = MockDirectoryService();
    when(dirService.findEmulatorExecutable(argThat(isA<String>()), argThat(isA<String>())))
        .thenAnswer((_) async => null);
    when(dirService.linuxSyncPreset).thenReturn('default');
    strategy = RetroArchSaveStrategy(
      dirService,
      platform: PlatformInfo('windows', environment: {'APPDATA': tempDir.path, 'USERPROFILE': tempDir.path}),
    )..ps2SerialOverride = ((_) async => serial);
  });

  tearDown(() => tempDir.delete(recursive: true));

  group('whether the saves can be synced', () {
    test("shared cards: RomM's serial is used before the ROM is read", () async {
      strategy.ps2SerialOverride = ((_) async => fail('the ROM must not be read when RomM has the serial'));
      final fromRomm = Game(
        id: '77',
        name: 'Ace Combat 5',
        fsName: 'Ace Combat 5 (USA).chd',
        platformSlug: 'ps2',
        fileSize: 0,
        titleId: 'SLUS-20851',
      );
      expect(await strategy.saveSyncBlockedReason(fromRomm, romPath), isNull);
    });

    test('shared cards, serial unknown: blocked, and the user is told why', () async {
      serial = null;
      expect(await strategy.saveSyncBlockedReason(game, romPath), contains('serial'));
    });

    test('shared cards, serial read from the ROM: not blocked', () async {
      expect(await strategy.saveSyncBlockedReason(game, romPath), isNull);
    });
  });

  group('per-game cards (Shared Memory Cards off)', () {
    setUp(() async {
      final opts = Directory(p.join(raDir, 'config', 'LRPS2'))..createSync(recursive: true);
      File(p.join(opts.path, 'LRPS2.opt')).writeAsStringSync('pcsx2_shared_memory_cards = "disabled"\n');
    });

    test('without a serial every save on the game\'s own card is its own: not blocked, no wait', () async {
      serial = null;
      expect(await strategy.saveSyncBlockedReason(game, romPath), isNull);
      expect(await strategy.pullMustFinishBeforeLaunch(game, romPath), isFalse);
    });

    test('a game-specific option file wins over the core\'s', () async {
      File(p.join(raDir, 'config', 'LRPS2', 'Ace Combat 5 (USA).opt'))
          .writeAsStringSync('pcsx2_shared_memory_cards = "enabled"\n');
      expect(await strategy.pullMustFinishBeforeLaunch(game, romPath), isTrue);
    });
  });

  test('shared cards: the pull finishes before LRPS2 starts', () async {
    expect(await strategy.pullMustFinishBeforeLaunch(game, romPath), isTrue);
  });

  test('other RetroArch platforms are not affected', () async {
    final snes = Game(id: '1', name: 'Zelda', fsName: 'Zelda.sfc', platformSlug: 'snes', fileSize: 0);
    expect(await strategy.pullMustFinishBeforeLaunch(snes, 'Zelda.sfc'), isFalse);
    expect(await strategy.saveSyncBlockedReason(snes, 'Zelda.sfc'), isNull);
  });

  group('Ps2SaveFolders', () {
    test('lrps2UsesSharedCards: the first file that sets it wins; shared by default', () {
      expect(Ps2SaveFolders.lrps2UsesSharedCards([]), isTrue);
      expect(Ps2SaveFolders.lrps2UsesSharedCards(['x = "1"\npcsx2_shared_memory_cards = "disabled"']), isFalse);
      expect(
        Ps2SaveFolders.lrps2UsesSharedCards([
          'pcsx2_shared_memory_cards = "enabled"',
          'pcsx2_shared_memory_cards = "disabled"',
        ]),
        isTrue,
      );
    });

    test('isSaveOf matches the serial after the region prefix', () {
      expect(Ps2SaveFolders.isSaveOf('BASLUS-20851AC5', 'SLUS-20851'), isTrue);
      expect(Ps2SaveFolders.isSaveOf('BESCES-52438GAMEDATA', 'SCES-52438'), isTrue);
      expect(Ps2SaveFolders.isSaveOf('BASLUS-20852AC5', 'SLUS-20851'), isFalse);
      expect(Ps2SaveFolders.isSaveOf('BASLUS', 'SLUS-20851'), isFalse);
      expect(Ps2SaveFolders.isSaveOf('baslus_20851ac5', 'slus-20851'), isTrue);
    });
  });
}
