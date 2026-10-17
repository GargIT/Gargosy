// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:gargosy/core/emulator/emulator_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/storage/directory_service.dart';

class MAMEStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  MAMEStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'MAME';

  @override
  String get emulatorId => 'mame';

  @override
  List<String> get supportedSlugs => ['arcade', 'mame'];

  @override
  String get windowsExecutable => 'mame.exe';

  @override
  String get linuxExecutable => 'mame';

  @override
  bool get supportsSaveSync => false;

  /// Gargosy (#62): states sync through RomM (MameSaveStrategy, states only).
  @override
  bool get supportsStateSync => true;

  @override
  bool get supportsStateLoadOnLaunch => true;

  /// MAME: `-state <file>` loads the state at start; a full path is taken
  /// as it is (src/emu/machine.cpp, compose_saveload_filename).
  @override
  List<String> stateLoadArgs(String statePath) => ['-state', statePath];

  @override
  String resolveSavePath(Game game) => '';
}
