// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:gargosy/core/emulator/emulator_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/duckstation_state_file.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:path/path.dart' as p;

class DuckstationStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  DuckstationStrategy(this._directoryService, {super.platform});

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  List<String> get launchArgs => ['-batch', '-fullscreen'];

  @override
  String get name => 'DuckStation';

  @override
  String get emulatorId => 'duckstation';

  @override
  List<String> get supportedSlugs => ['ps1', 'playstation', 'psx'];

  @override
  String get windowsExecutable => 'duckstation-qt-x64-ReleaseLTCG.exe';

  @override
  String get linuxExecutable => 'DuckStation.AppImage';

  @override
  String get macosExecutable => 'DuckStation.app/Contents/MacOS/DuckStation';

  @override
  bool get supportsSaveSync => true;

  @override
  bool get supportsStateSync => true;

  @override
  bool get supportsStateLoadOnLaunch => true;

  /// DuckStation: `-statefile <filename>` loads the given state at boot.
  @override
  List<String> stateLoadArgs(String statePath) => ['-statefile', statePath];

  /// Gargosy: a state records the disc's full path, and DuckStation opens
  /// that one when it differs from the running disc (a warning on another
  /// PC). DuckStation keeps the command line's path as given, so [romPath].
  @override
  Uint8List? stateForRom(Uint8List state, String romPath) => DuckstationStateFile.withMediaPath(state, romPath);

  @override
  String resolveSavePath(Game game) {
    if (platform.isMacOS) {
      final home = platform.environment['HOME'];
      if (home != null) {
        return '$home/Library/Application Support/DuckStation/';
      }
    }
    return '';
  }

  @override
  Future<void> postInstall(String installDir) async {
    if (platform.isWindows) {
      // DuckStation requires a portable.txt file in the SAME directory as the executable to run in portable mode.
      final exePath = await _directoryService.findEmulatorExecutable(emulatorId, windowsExecutable);
      final targetDir = exePath != null ? io.File(exePath).parent.path : installDir;

      final portableTxt = io.File(p.join(targetDir, 'portable.txt'));
      if (!await portableTxt.exists()) {
        await portableTxt.create();
        debugPrint('[DuckStation] Created portable.txt at $targetDir to enable portable mode.');
      }
    }
  }
}
