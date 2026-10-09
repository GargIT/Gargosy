// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:gargosy/core/emulator/emulator_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/storage/directory_service.dart';

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

  @override
  String resolveSavePath(Game game) => '';
}
