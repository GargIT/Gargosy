import 'package:path/path.dart' as p;

import '../core/save/save_sync_service.dart';
import '../core/save/strategies/duckstation_save_strategy.dart';
import '../profiles/profile_paths.dart';
import 'sigil_save_strategy.dart';
import 'sigil_state_store.dart';

/// The profile's save strategies through sigil, for [SaveSyncService]'s
/// `wrapSaves`: each emulator sigil syncs gets a [SigilSaveStrategy] on its
/// folder in the profile, with sigil's state and units under
/// `profiles\<id>\sigil\`. sigil.dll is checked when Gargosy starts, which
/// doesn't go on without it (#57), so there is no other save code to fall back to.
SaveStrategyWrapper sigilSavesFor(ProfilePaths paths) {
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
