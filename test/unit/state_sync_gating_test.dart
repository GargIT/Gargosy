// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/emulator_registry_data.dart';
import 'package:gargosy/core/emulator/strategy_registry.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/core/save/save_sync_service.dart';
import 'package:gargosy/core/save/state_sync_capable.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Any game: the lookup goes by emulator (MAME's states-only strategy too).
final _anyGame = Game(id: '1', name: 'Game', fileSize: 0);

void main() {
  test('every emulator advertising state sync has a StateSyncCapable save strategy', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final directoryService = DirectoryService(prefs);
    final registry = StrategyRegistry(directoryService, prefs);
    final saveSync = SaveSyncService(
      RommService(
        RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 'k'),
        skipConnectivityCheck: true,
      ),
      directoryService,
      registry,
      prefs,
    );

    final advertising = <String>[];
    for (final definition in kEmulatorDefinitions) {
      final id = definition['id'] as String;
      final strategy = registry.getStrategyById(id);
      if (strategy == null || !strategy.supportsStateSync) continue;
      advertising.add(id);
      expect(saveSync.stateStrategyForGame(_anyGame, emulatorId: id), isA<StateSyncCapable>(),
          reason: '$id advertises supportsStateSync but its save strategy is not StateSyncCapable');
    }

    expect(advertising, unorderedEquals(['duckstation', 'pcsx2', 'retroarch', 'ppsspp', 'dolphin', 'mgba', 'mame']),
        reason: 'DuckStation, PCSX2, RetroArch, PPSSPP (#59), Dolphin (#60), mGBA (#61) and MAME (#62) are the emulators with state sync so far');
  });

  test('every emulator that can load a state on launch has a StateSyncCapable save strategy', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final directoryService = DirectoryService(prefs);
    final registry = StrategyRegistry(directoryService, prefs);
    final saveSync = SaveSyncService(
      RommService(
        RomMConfig(baseUrl: 'https://romm.example.com', username: '', password: '', apiKey: 'k'),
        skipConnectivityCheck: true,
      ),
      directoryService,
      registry,
      prefs,
    );

    final advertising = <String>[];
    for (final definition in kEmulatorDefinitions) {
      final id = definition['id'] as String;
      final strategy = registry.getStrategyById(id);
      if (strategy == null || !strategy.supportsStateLoadOnLaunch) continue;
      advertising.add(id);
      expect(saveSync.stateStrategyForGame(_anyGame, emulatorId: id), isA<StateSyncCapable>(),
          reason: '$id advertises supportsStateLoadOnLaunch but its save strategy is not StateSyncCapable');
    }

    expect(advertising, unorderedEquals(['duckstation', 'pcsx2', 'retroarch', 'ppsspp', 'dolphin', 'mgba', 'mame']),
        reason: 'DuckStation, PCSX2, RetroArch, PPSSPP (#59), Dolphin (#60), mGBA (#61) and MAME (#62) are the emulators that can load a state on launch so far');
  });

  test('emulators default to not loading a state on launch', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final registry = StrategyRegistry(DirectoryService(prefs), prefs);

    expect(registry.getStrategyById('cemu')!.supportsStateLoadOnLaunch, isFalse); // Cemu has no states
  });

  test('emulators default to not supporting state sync', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    final registry = StrategyRegistry(DirectoryService(prefs), prefs);

    expect(registry.getStrategyById('cemu')!.supportsStateSync, isFalse); // Cemu has no states
  });
}
