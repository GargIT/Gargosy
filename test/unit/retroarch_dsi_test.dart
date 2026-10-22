import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/retroarch_core_list.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;

import 'save_sync_regression_test.mocks.dart';

/// DSi games in RetroArch: only melonDS DS runs them, and a DSiWare game's
/// save is its title data (`<rom>.public.sav` …), never a `.srm`.
void main() {
  group('the core for a DSi game', () {
    test('is melonDS DS, the only core offered', () {
      expect(getDefaultCoreForSlug('nintendo-dsi'), 'melondsds_libretro');
      expect(getCoresForSlug('nintendo-dsi').map((c) => c.id), ['melondsds_libretro']);
      expect(getDefaultCoreForSlug('nds'), 'melonds_libretro', reason: 'DS games keep their default');
    });

    test("the DS platform's chosen core doesn't apply to a DSi game; the DSi platform's own does", () {
      expect(chosenCoreFor({'nds': 'melonds_libretro'}, 'nintendo-dsi'), isNull);
      expect(chosenCoreFor({'nintendo-dsi': 'melondsds_libretro'}, 'nintendo-dsi'), 'melondsds_libretro');
      expect(chosenCoreFor({'nds': 'desmume2015_libretro'}, 'nds'), 'desmume2015_libretro');
      expect(
        chosenCoreFor({'nintendo-ds-lite': 'melondsds_libretro'}, 'nintendo-ds-lite'),
        'melondsds_libretro',
        reason: "a platform's page saves its choice under RomM's slug",
      );
    });
  });

  group("a DSiWare game's save", () {
    late Directory tempDir;
    late String saveDir;
    late RetroArchSaveStrategy strategy;
    const stem = "Zuma's Revenge! (USA)";
    final game = Game(id: '1', name: "Zuma's Revenge!", fsName: '$stem.nds', platformSlug: 'nintendo-dsi', fileSize: 0);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ra_dsi_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);
      saveDir = p.join(tempDir.path, 'saves');
      await File(p.join(configDir, 'retroarch.cfg'))
          .writeAsString(['savefile_directory = "$saveDir"', 'sort_savefiles_enable = "false"'].join('\n'));
      await Directory(saveDir).create(recursive: true);
      final dirService = MockDirectoryService();
      when(dirService.findEmulatorExecutable(argThat(isA<String>()), argThat(isA<String>())))
          .thenAnswer((_) async => null);
      when(dirService.linuxSyncPreset).thenReturn('default');
      when(dirService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
          .thenAnswer((_) async => configDir);
      strategy = RetroArchSaveStrategy(
        dirService,
        platform: PlatformInfo('linux', environment: {'HOME': tempDir.path}),
      );
    });

    tearDown(() => tempDir.delete(recursive: true));

    String romPath() => p.join(tempDir.path, 'roms', '$stem.nds');
    List<String> savesOnDisk() =>
        Directory(saveDir).listSync().whereType<File>().map((f) => p.basename(f.path)).toList()..sort();

    test('is every part of its title data, and not a stray .srm beside it', () async {
      for (final name in ['$stem.public.sav', '$stem.private.sav', '$stem.public.srm', 'Other.public.sav']) {
        File(p.join(saveDir, name)).writeAsBytesSync([1]);
      }
      final files = await strategy.getSaveFiles(game, romPath());
      expect(files.map((f) => p.basename(f.path)).toList()..sort(), ['$stem.private.sav', '$stem.public.sav']);
    });

    test('comes back under the name melonDS DS reads, never as .srm', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(await strategy.restoreSave(game, romPath(), bytes, '$stem.public.sav'), isTrue);
      expect(await strategy.restoreSave(game, romPath(), bytes, 'Zuma [2026].private.sav'), isTrue);
      expect(savesOnDisk(), ['$stem.private.sav', '$stem.public.sav']);
    });

    test('a cartridge .sav still becomes .srm', () async {
      await strategy.restoreSave(game, romPath(), Uint8List.fromList([1]), 'Other.sav');
      expect(savesOnDisk(), ['Other.srm']);
    });
  });
}
