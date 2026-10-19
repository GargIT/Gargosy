// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:gargosy/core/emulator/emulator_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/storage/directory_service.dart';

class AzaharStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  AzaharStrategy(this._directoryService);

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'Azahar';

  @override
  String get emulatorId => 'azahar';

  @override
  List<String> get supportedSlugs => [
    '3ds',
    'n3ds',
    'nintendo-3ds',
    'nintendo3ds',
    'new-nintendo-3ds',
    'new-nintendo-3ds-xl',
  ];

  @override
  String get windowsExecutable => 'azahar.exe';

  @override
  String get linuxExecutable => 'azahar.AppImage';

  @override
  String get macosExecutable => 'Azahar.app/Contents/MacOS/azahar';

  @override
  bool get supportsSaveSync => true;

  /// Gargosy (#64): states sync through RomM (AzaharSaveStrategy). Azahar
  /// has no option to load a state at start, so there's no Resume: a state
  /// that came down is loaded from Azahar's own menu.
  @override
  bool get supportsStateSync => true;

  @override
  String resolveSavePath(Game game) => '';
}
