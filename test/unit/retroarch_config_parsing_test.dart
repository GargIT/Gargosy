// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/retroarch_save_strategy.dart';
import 'package:gargosy/core/save/save_strategy.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;

import 'save_sync_regression_test.mocks.dart';

void main() {
  late MockDirectoryService mockDirService;

  setUp(() {
    mockDirService = MockDirectoryService();
    when(mockDirService.findEmulatorExecutable(
            argThat(isA<String>()), argThat(isA<String>())))
        .thenAnswer((_) async => null);
    when(mockDirService.linuxSyncPreset).thenReturn('default');
  });

  group('RetroArch config parsing: sort_savefiles_enable', () {


    test('sort_savefiles_enable not set defaults to true (RetroArch default)', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_sort_default_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'video_fullscreen = "false"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves', 'mGBA')).create(recursive: true);

      when(mockDirService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
          .thenAnswer((_) async => configDir);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final game = Game(id: '1', name: 'Pokemon', platformSlug: 'gba', fileSize: 0);
      final romPath = p.join(tempDir.path, 'roms', 'Pokemon.gba');
      final result = await strategy.getSaveDir(game, romPath);

      expect(result, isNotNull);
      expect(result, endsWith('mGBA'),
          reason: 'Default should be true (append core subfolder)');

      await tempDir.delete(recursive: true);
    });


    test('sort_savefiles_enable with extra whitespace and no quotes', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_sort_ws_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'sort_savefiles_enable = false',
        'video_fullscreen = "false"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves')).create(recursive: true);

      when(mockDirService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
          .thenAnswer((_) async => configDir);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final game = Game(id: '1', name: 'Pokemon', platformSlug: 'gba', fileSize: 0);
      final romPath = p.join(tempDir.path, 'roms', 'Pokemon.gba');
      final result = await strategy.getSaveDir(game, romPath);

      expect(result, isNotNull);
      expect(result, isNot(endsWith('mGBA')),
          reason: 'Unquoted false should also be parsed correctly');

      await tempDir.delete(recursive: true);
    });
  });


  group('RetroArch config parsing: static retroarchCoreSaveDir', () {
    test('sort_savefiles_enable=false returns flat dir without core subfolder', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_static_sort_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'sort_savefiles_enable = "false"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves')).create(recursive: true);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final result = await SaveStrategy.retroarchCoreSaveDir(
        mockDirService, 'mGBA', platform: platform);

      expect(result, isNotNull);
      expect(result, equals(p.join(tempDir.path, 'saves')),
          reason: 'sort=false should return flat dir, not core subfolder');

      await tempDir.delete(recursive: true);
    });

    test('sort_savefiles_enable=true returns core subfolder', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_static_sort_true_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'sort_savefiles_enable = "true"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves', 'mGBA')).create(recursive: true);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final result = await SaveStrategy.retroarchCoreSaveDir(
        mockDirService, 'mGBA', platform: platform);

      expect(result, isNotNull);
      expect(result, endsWith('mGBA'),
          reason: 'sort=true should append core subfolder');

      await tempDir.delete(recursive: true);
    });

    test('sort_savefiles_enable not set defaults to true', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_static_default_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
      ].join('\n'));

      await Directory(p.join(tempDir.path, 'saves', 'mGBA')).create(recursive: true);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final result = await SaveStrategy.retroarchCoreSaveDir(
        mockDirService, 'mGBA', platform: platform);

      expect(result, isNotNull);
      expect(result, endsWith('mGBA'),
          reason: 'Default should be true (append core subfolder)');

      await tempDir.delete(recursive: true);
    });
  });

  group('RetroArch EmuDeck-for-Windows detection', () {

    test('falls back to normal Windows resolution when emudeck root absent', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_no_emudeck_win_');
      final exeDir = p.join(tempDir.path, 'RetroArch-Win64');
      await Directory(exeDir).create(recursive: true);
      final exePath = p.join(exeDir, 'RetroArch.exe');
      await File(exePath).writeAsString('');

      when(mockDirService.findEmulatorExecutable('retroarch', 'RetroArch.exe'))
          .thenAnswer((_) async => exePath);

      final platform = PlatformInfo('windows', environment: {
        'USERPROFILE': tempDir.path,
        'APPDATA': p.join(tempDir.path, 'AppData', 'Roaming'),
      });
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final game = Game(id: '1', name: 'Pokemon', platformSlug: 'gba', fileSize: 0);
      final romPath = p.join(tempDir.path, 'roms', 'Pokemon.gba');
      final result = await strategy.getSaveDir(game, romPath);

      expect(result, equals(p.join(exeDir, 'saves', 'mGBA')),
          reason: 'Without an emudeck folder present, should resolve relative to the exe as before');

      await tempDir.delete(recursive: true);
    });
  });

  group('RetroArch save file matching (regression for #95)', () {
    test('does NOT return an unrelated game\'s save file when nothing matches by name', () async {
      // Reproduces the reported bug: playing "Bank Heist" (Atari 2600/Stella,
      // no battery-backed save, only savestates) while a leftover .srm from a
      // completely unrelated game ("Dragon Ball - Advanced Adventure") sits in
      // the same core save folder. Previously, the "last resort: any file"
      // fallback would pick up and return that unrelated file, causing it to
      // be uploaded to RomM under Bank Heist's entry.
      final tempDir = await Directory.systemTemp.createTemp('ra_wrong_save_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'sort_savefiles_enable = "true"',
      ].join('\n'));

      final saveDir = p.join(tempDir.path, 'saves', 'Atari 2600');
      await Directory(saveDir).create(recursive: true);
      // Unrelated leftover save from a completely different game.
      await File(p.join(saveDir, 'Dragon Ball - Advanced Adventure.srm'))
          .writeAsBytes([1, 2, 3]);

      when(mockDirService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
          .thenAnswer((_) async => configDir);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final game = Game(id: '1', name: 'Bank Heist', platformSlug: 'atari2600', fileSize: 0);
      final romPath = p.join(tempDir.path, 'roms', 'Bank Heist.a26');

      final files = await strategy.getSaveFiles(game, romPath, syncMode: 'saves');

      expect(files, isEmpty,
          reason: 'Must not fall back to an unrelated save file just because it exists in the directory');

      await tempDir.delete(recursive: true);
    });

    test('still returns the correctly name-matched save file', () async {
      final tempDir = await Directory.systemTemp.createTemp('ra_right_save_');
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);

      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "${p.join(tempDir.path, 'saves')}"',
        'sort_savefiles_enable = "true"',
      ].join('\n'));

      final saveDir = p.join(tempDir.path, 'saves', 'mGBA');
      await Directory(saveDir).create(recursive: true);
      await File(p.join(saveDir, 'Pokemon.srm')).writeAsBytes([1, 2, 3]);

      when(mockDirService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
          .thenAnswer((_) async => configDir);

      final platform = PlatformInfo('linux', environment: {'HOME': tempDir.path});
      final strategy = RetroArchSaveStrategy(mockDirService, platform: platform);

      final game = Game(id: '1', name: 'Pokemon', platformSlug: 'gba', fileSize: 0);
      final romPath = p.join(tempDir.path, 'roms', 'Pokemon.gba');

      final files = await strategy.getSaveFiles(game, romPath, syncMode: 'saves');

      expect(files.length, 1);
      expect(files.first.path, equals(p.join(saveDir, 'Pokemon.srm')));

      await tempDir.delete(recursive: true);
    });

    /// A flat save folder (sort_savefiles_enable=false) holding [saves];
    /// returns the saves getSaveFiles picks for a game whose ROM is [romName].
    Future<List<String>> pick(String romName, List<String> saves) async {
      final tempDir = await Directory.systemTemp.createTemp('ra_pick_save_');
      addTearDown(() => tempDir.delete(recursive: true));
      final configDir = p.join(tempDir.path, '.config', 'retroarch');
      await Directory(configDir).create(recursive: true);
      final saveDir = p.join(tempDir.path, 'saves');
      await File(p.join(configDir, 'retroarch.cfg')).writeAsString([
        'savefile_directory = "$saveDir"',
        'sort_savefiles_enable = "false"',
      ].join('\n'));
      await Directory(saveDir).create(recursive: true);
      for (final s in saves) {
        await File(p.join(saveDir, s)).writeAsBytes([1, 2, 3]);
      }
      when(mockDirService.getEmulatorAppSupportDirectory('retroarch', platformSlug: anyNamed('platformSlug')))
          .thenAnswer((_) async => configDir);
      final strategy = RetroArchSaveStrategy(mockDirService,
          platform: PlatformInfo('linux', environment: {'HOME': tempDir.path}));
      final game = Game(id: '1', name: romName, fsName: romName, platformSlug: 'psx', fileSize: 0);
      final files = await strategy.getSaveFiles(game, p.join(tempDir.path, 'roms', romName), syncMode: 'saves');
      return files.map((f) => p.basename(f.path)).toList();
    }

    test('a sequel does not pick up the first game\'s save', () async {
      expect(await pick('Crash Bandicoot 2 - Cortex Strikes Back (Europe).cue', ['Crash Bandicoot (Europe).srm']),
          isEmpty);
      expect(await pick('Crash Bandicoot 2 (Europe).cue', ['Crash Bandicoot (Europe).srm']), isEmpty);
    });

    test('the first game does not pick up a sequel\'s save', () async {
      expect(await pick('Crash Bandicoot.cue', ['Crash Bandicoot 2 (Europe).srm']), isEmpty);
    });

    test('an exact name wins over a same-title save for another region', () async {
      expect(await pick('Crash Bandicoot (USA).cue', ['Crash Bandicoot (Europe).srm', 'Crash Bandicoot (USA).srm']),
          ['Crash Bandicoot (USA).srm']);
    });

    test('a save for the same title under another region or word order still matches', () async {
      expect(await pick('Crash Bandicoot (Europe).cue', ['Crash Bandicoot (USA).srm']), ['Crash Bandicoot (USA).srm']);
      expect(await pick('The Legend of Zelda (USA).sfc', ['Legend of Zelda, The (Europe) [!].srm']),
          ['Legend of Zelda, The (Europe) [!].srm']);
    });

    test('isSaveNamedFor needs the stem followed by an extension', () {
      expect(RetroArchSaveStrategy.isSaveNamedFor('Pokemon.srm', 'pokemon'), isTrue);
      expect(RetroArchSaveStrategy.isSaveNamedFor('pokemon.0.mcr', 'Pokemon'), isTrue);
      expect(RetroArchSaveStrategy.isSaveNamedFor('Pokemon Gold.srm', 'Pokemon'), isFalse);
      expect(RetroArchSaveStrategy.isSaveNamedFor('Crash Bandicoot 2.srm', 'Crash Bandicoot'), isFalse);
    });

    test('isSameTitle compares every word, numbers included', () {
      expect(RetroArchSaveStrategy.isSameTitle('Final Fantasy II (USA)', 'Final Fantasy (USA).srm'), isFalse);
      expect(RetroArchSaveStrategy.isSameTitle('Final Fantasy (USA)', 'Final Fantasy II (USA).srm'), isFalse);
      expect(RetroArchSaveStrategy.isSameTitle('Final Fantasy II (USA)', 'final fantasy ii (europe).srm'), isTrue);
      expect(RetroArchSaveStrategy.isSameTitle('(USA)', 'Other (USA).srm'), isFalse);
    });
  });
}
