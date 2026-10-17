// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:gargosy/core/emulator/emulator_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/flycast_save_strategy.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:path/path.dart' as p;

class FlycastStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  FlycastStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'Flycast';

  @override
  String get emulatorId => 'flycast';

  @override
  List<String> get supportedSlugs => ['dc', 'dreamcast', 'naomi', 'naomi2', 'atomiswave', 'cave', 'hikaru'];

  @override
  String get windowsExecutable => 'flycast.exe';

  @override
  String get linuxExecutable => 'flycast.AppImage';

  @override
  String get macosExecutable => 'Flycast.app/Contents/MacOS/Flycast';

  @override
  bool get supportsSaveSync => false;

  /// Gargosy (#63): states sync through RomM (FlycastSaveStrategy, states only).
  @override
  bool get supportsStateSync => true;

  @override
  bool get supportsStateLoadOnLaunch => true;

  /// Flycast has no option to load a state file; it loads its own slot at
  /// boot when `Dreamcast.AutoLoadState` is on (core/emulator.cpp). The
  /// state is in the profile's state folder under its slot's name, so the
  /// slot is set for this launch only (`-config` values aren't saved).
  @override
  List<String> stateLoadArgs(String statePath) => [
        '-config',
        'config:Dreamcast.AutoLoadState=yes,config:Dreamcast.SavestateSlot=${FlycastSaveStrategy.slotNumber(p.basename(statePath)) ?? 0}',
      ];

  @override
  bool canLoadState(String fileName) => FlycastSaveStrategy.slotNumber(fileName) != null;

  @override
  String resolveSavePath(Game game) => '';
}
