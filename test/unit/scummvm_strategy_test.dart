// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategies/scummvm_strategy.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/rom_constants.dart';
import 'package:gargosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'strategy_registry_test.mocks.dart';

void main() {
  group('ScummVMStrategy', () {
    test('starts the game folder with --auto-detect --path, no bare path argument', () {
      // ScummVM rejects a bare folder argument as an unknown game target.
      expect(ScummVMStrategy.gameArgs('/games/Drascula The Vampire'), [
        '--auto-detect',
        '--path=/games/Drascula The Vampire',
      ]);
    });

    test('a game folder is used as is, a file inside it resolves to the folder', () async {
      final dir = await Directory.systemTemp.createTemp('scummvm game');
      addTearDown(() => dir.delete(recursive: true));
      final dataFile = File(p.join(dir.path, 'packet.001'))..writeAsStringSync('x');
      expect(ScummVMStrategy.gameFolderFor(dir.path), dir.path);
      expect(ScummVMStrategy.gameFolderFor(dataFile.path), dir.path);
    });

    test('scummvm is a folder-game platform', () {
      expect(RomConstants.isFolderGamePlatform('scummvm'), isTrue);
      expect(RomConstants.isFolderGamePlatform('ScummVM'), isTrue);
      expect(RomConstants.isFolderGamePlatform('psx'), isFalse);
      expect(RomConstants.isFolderGamePlatform(null), isFalse);
    });

    test('is registered for the scummvm slug on every desktop OS', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
      for (final os in ['windows', 'linux', 'macos']) {
        final registry = StrategyRegistry(MockDirectoryService(), prefs, platform: PlatformInfo(os));
        expect(registry.getStrategyForSlug('scummvm')?.emulatorId, 'scummvm', reason: os);
      }
    });
  });
}
