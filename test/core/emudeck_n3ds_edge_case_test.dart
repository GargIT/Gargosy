// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/rom_constants.dart';

void main() {
  group('EmuDeck n3ds folder edge case', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('freegosy_n3ds_test_');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('DirectoryService.getRomDirectory', () {
      Future<DirectoryService> createService(String preset) async {
        final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
        final service = DirectoryService(prefs);
        service.romsRootPath = tempDir.path;
        service.linuxSyncPreset = preset;
        return service;
      }



      test('uses slug directly as folder name on default preset', () async {
        final service = await createService('default');

        final game = Game(id: '1', name: 'Test', platformSlug: '3ds', fileSize: 0);
        final romDir = await service.getRomDirectory(game);

        expect(romDir, p.join(tempDir.path, '3ds'));
      });
    });


    group('Scanner folder alias map', () {
      test('exposes platformFolderCanonicalMap for scanner reverse lookup', () {
        expect(DirectoryService.platformFolderCanonicalMap['n3ds'], equals('3ds'));
        expect(DirectoryService.platformFolderCanonicalMap['nintendo-3ds'], equals('3ds'));
        expect(DirectoryService.platformFolderCanonicalMap['nintendo3ds'], equals('3ds'));
        expect(DirectoryService.platformFolderCanonicalMap['new-nintendo-3ds'], equals('3ds'));
        expect(DirectoryService.platformFolderCanonicalMap['new-nintendo-3ds-xl'], equals('3ds'));
        expect(DirectoryService.platformFolderCanonicalMap['3ds'], isNull);
      });
    });

    group('RomConstants platformExtensions for n3ds', () {
      test('includes n3ds as a known platform extension key', () {
        final extensions = RomConstants.platformExtensions['n3ds'];
        expect(extensions, isNotNull);
        expect(extensions!.contains('.3ds'), isTrue);
        expect(extensions.contains('.cia'), isTrue);
        expect(extensions.contains('.app'), isTrue);
      });

      test('includes all 3DS variant extension keys', () {
        for (final slug in ['n3ds', 'nintendo-3ds', 'nintendo3ds', 'new-nintendo-3ds', 'new-nintendo-3ds-xl']) {
          final extensions = RomConstants.platformExtensions[slug];
          expect(extensions, isNotNull, reason: 'slug "$slug" should have extension entries');
          expect(extensions!.contains('.3ds'), isTrue, reason: 'slug "$slug" missing .3ds');
          expect(extensions.contains('.cia'), isTrue, reason: 'slug "$slug" missing .cia');
          expect(extensions.contains('.app'), isTrue, reason: 'slug "$slug" missing .app');
        }
      });
    });
  });
}
