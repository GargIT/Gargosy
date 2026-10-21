import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emulator/firmware_service.dart';
import '../providers/engine_providers.dart';
import '../providers/romm_providers.dart';

/// BIOS files from RomM's firmware into the shared `bios\` (spec §6: every
/// profile's emulators point there), through Freegosy's firmware sync: each
/// platform's firmware goes where its emulator expects it, and a file
/// already there (with the right checksum when one is known) isn't fetched
/// again. Uses the open profile's RomM account; every profile gets them.
class BiosSync {
  BiosSync(this._firmware);
  final FirmwareService _firmware;

  /// For the platforms [emulatorId] plays; returns how many files came down.
  Future<int> forEmulator(String emulatorId) =>
      _counting((onProgress) => _firmware.syncFirmwareForEmulator(emulatorId, onProgress: onProgress));

  /// For one platform ([slug]), into its emulator's folder.
  Future<int> forPlatform(String slug) =>
      _counting((onProgress) => _firmware.syncFirmwareForPlatform(slug, onProgress: onProgress));

  /// For every installed emulator (ids in [installed]).
  Future<int> forAll(Set<String> installed) =>
      _counting((onProgress) => _firmware.syncAllFirmware(onProgress: onProgress, installedEmulatorIds: installed));

  Future<int> _counting(Future<void> Function(FirmwareProgressCallback) run) async {
    final files = <String>{};
    await run((name, _, _) => files.add(name));
    return files.length;
  }
}

final biosSyncProvider = Provider<BiosSync?>((ref) {
  final romm = ref.watch(rommServiceProvider);
  final dirs = ref.watch(launchDirectoriesProvider);
  final registry = ref.watch(strategyRegistryProvider);
  if (romm == null || dirs == null || registry == null) return null;
  return BiosSync(FirmwareService(romm, dirs, registry));
});
