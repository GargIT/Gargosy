import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/save/save_sync_service.dart';
import '../core/save/strategies/duckstation_save_strategy.dart';
import '../profiles/profile_paths.dart';
import 'sigil_library.dart';
import 'sigil_save_strategy.dart';
import 'sigil_state_store.dart';

/// The profile's save strategies through sigil, for [SaveSyncService]'s
/// `wrapSaves`: each emulator sigil syncs gets a [SigilSaveStrategy] on its
/// folder in the profile, with sigil's state and units under
/// `profiles\<id>\sigil\`. Null when sigil.dll can't be used (the old
/// strategies stay; the log says why).
SaveStrategyWrapper? sigilSavesFor(ProfilePaths paths) {
  try {
    SigilLibrary.open();
  } on SigilUnavailable catch (e) {
    debugPrint('[Sigil] saves through the old code: $e');
    return null;
  }
  final root = p.join(paths.dir, 'sigil');
  final states = SigilStateStore(root);
  final units = p.join(root, 'units');
  return (emulatorId, base) =>
      SigilSaveStrategy.forEmulator(
        emulatorId,
        base: base,
        emulatorDir: () => paths.emulatorDir(emulatorId),
        states: states,
        unitsDir: units,
        content: base is DuckstationSaveStrategy ? base.sigilCard : null,
      ) ??
      base;
}
