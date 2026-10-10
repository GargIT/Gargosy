// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/custom_emulator_config.dart';

void main() {
  group('CustomEmulatorConfig - commandOverride', () {
    test('isCommandOverride returns true when commandOverride is set', () {
      final config = CustomEmulatorConfig(
        id: 'test-flatpak',
        name: 'RetroArch Flatpak',
        platforms: ['ps1', 'psx'],
        executablePath: '/usr/bin/flatpak',
        commandOverride: 'flatpak run org.libretro.RetroArch',
        saveMethod: CustomSaveMethod.file,
        savePath: '/home/user/saves',
      );

      expect(config.isCommandOverride, isTrue);
      expect(config.commandOverride, 'flatpak run org.libretro.RetroArch');
    });

    test('isCommandOverride returns false when commandOverride is null', () {
      final config = CustomEmulatorConfig(
        id: 'test-native',
        name: 'PCSX2 Native',
        platforms: ['ps2'],
        executablePath: '/usr/bin/pcsx2',
        saveMethod: CustomSaveMethod.file,
        savePath: '/home/user/saves',
      );

      expect(config.isCommandOverride, isFalse);
      expect(config.commandOverride, isNull);
    });

    test('isCommandOverride returns false when commandOverride is empty', () {
      final config = CustomEmulatorConfig(
        id: 'test-empty',
        name: 'Empty Command',
        platforms: ['nes'],
        executablePath: '/usr/bin/emu',
        commandOverride: '',
        saveMethod: CustomSaveMethod.file,
        savePath: '/home/user/saves',
      );

      expect(config.isCommandOverride, isFalse);
    });

    test('toJson includes commandOverride when set', () {
      final config = CustomEmulatorConfig(
        id: 'test-json',
        name: 'RetroArch Flatpak',
        platforms: ['ps1'],
        executablePath: '/usr/bin/flatpak',
        commandOverride: 'flatpak run org.libretro.RetroArch',
        saveMethod: CustomSaveMethod.file,
        savePath: '/home/user/saves',
      );

      final json = config.toJson();
      expect(json['commandOverride'], 'flatpak run org.libretro.RetroArch');
    });

    test('toJson omits commandOverride when null', () {
      final config = CustomEmulatorConfig(
        id: 'test-json-null',
        name: 'Native',
        platforms: ['ps2'],
        executablePath: '/usr/bin/pcsx2',
        saveMethod: CustomSaveMethod.folder,
        savePath: '/home/user/saves',
      );

      final json = config.toJson();
      expect(json.containsKey('commandOverride'), isFalse);
    });

    test('fromJson restores commandOverride', () {
      final json = {
        'id': 'test-fromjson',
        'name': 'Restored RetroArch',
        'platforms': ['ps1', 'psx'],
        'executablePath': '/usr/bin/flatpak',
        'commandOverride': 'flatpak run org.libretro.RetroArch',
        'saveMethod': 'file',
        'savePath': '/home/user/saves',
      };

      final config = CustomEmulatorConfig.fromJson(json);
      expect(config.commandOverride, 'flatpak run org.libretro.RetroArch');
      expect(config.isCommandOverride, isTrue);
    });

    test('round-trip JSON serialization preserves commandOverride', () {
      final original = CustomEmulatorConfig(
        id: 'roundtrip',
        name: 'Dolphin Flatpak',
        platforms: ['gc', 'wii'],
        executablePath: '/usr/bin/flatpak',
        commandOverride: 'flatpak run org.DolphinEmu.dolphin-emu',
        saveMethod: CustomSaveMethod.folder,
        savePath: '/home/user/saves',
      );

      final json = original.toJson();
      final restored = CustomEmulatorConfig.fromJson(json);

      expect(restored.commandOverride, original.commandOverride);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.platforms, original.platforms);
      expect(restored.isCommandOverride, isTrue);
    });

    test('round-trip JSON serialization works without commandOverride', () {
      final original = CustomEmulatorConfig(
        id: 'roundtrip-native',
        name: 'mGBA',
        platforms: ['gba'],
        executablePath: '/usr/bin/mgba',
        saveMethod: CustomSaveMethod.file,
        savePath: '/home/user/saves',
      );

      final json = original.toJson();
      final restored = CustomEmulatorConfig.fromJson(json);

      expect(restored.commandOverride, isNull);
      expect(restored.isCommandOverride, isFalse);
    });
  });



  // Regression tests for issue #75: "Dolphin games with spaces in the
  // filename fail to launch". The real cause wasn't argv/quoting — it was
  // the ROM path falling outside Flatpak's default sandbox access
  // ($HOME, /run/media, /media). isOutsideFlatpakDefaultAccess is a pure
  // function with no process/IO dependency, so it's directly unit-testable.
}
