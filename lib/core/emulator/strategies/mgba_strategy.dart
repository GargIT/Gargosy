// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:gargosy/core/emulator/emulator_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/storage/directory_service.dart';

class MGBAStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  MGBAStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'mGBA';

  @override
  String get emulatorId => 'mgba';

  @override
  List<String> get supportedSlugs => ['gba', 'gbc', 'gb', 'game-boy-advance', 'game-boy-color', 'game-boy'];

  @override
  String get windowsExecutable => 'mGBA.exe';

  @override
  String get linuxExecutable => 'mgba';

  @override
  String get macosExecutable => 'mGBA.app/Contents/MacOS/mGBA';

  @override
  bool get supportsSaveSync => false;

  /// Gargosy (#61): states sync through RomM (MgbaSaveStrategy).
  @override
  bool get supportsStateSync => true;

  @override
  bool get supportsStateLoadOnLaunch => true;

  /// mGBA: `-t <file>` loads the state when the game starts.
  @override
  List<String> stateLoadArgs(String statePath) => ['-t', statePath];

  @override
  String resolveSavePath(Game game) => '';
}
