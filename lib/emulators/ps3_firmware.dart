import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../profiles/app_root.dart';
import '../profiles/profile_providers.dart';
import '../providers/engine_providers.dart';
import 'bios_links.dart';
import 'profile_directories.dart';
import 'rpcs3_config.dart';

/// Why the PS3 firmware couldn't be installed; the UI shows [message].
class Ps3FirmwareException implements Exception {
  const Ps3FirmwareException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The PS3 firmware for RPCS3 (issue #10): RomM's `PS3UPDAT.PUP` in `bios\`,
/// installed once with `rpcs3.exe --installfw` into the shared
/// `emulators\rpcs3\dev_flash\` every profile reads (see [Rpcs3Config]).
class Ps3Firmware {
  Ps3Firmware(this.root, this.dirs);

  final AppRoot root;
  final ProfileLaunchDirectories dirs;

  static const pupName = 'PS3UPDAT.PUP';

  /// The firmware file in `bios\`, or null.
  io.File? get pup => findBiosFile(root.bios, const [pupName]);

  /// Whether a firmware is installed in the shared dev_flash (its VSH).
  bool get installed => io.File(p.join(root.emulators, 'rpcs3', 'dev_flash', 'vsh', 'module', 'vsh.self')).existsSync();

  static List<String> commandLine(String pup) => ['--installfw', pup];

  /// Installs [pup] with RPCS3 at [exePath]; RPCS3 shows its own progress.
  Future<void> install(String exePath) async {
    final file = pup;
    if (file == null) {
      throw const Ps3FirmwareException('There is no $pupName in bios\\. Get BIOS files from RomM first '
          '(RomM keeps the PS3 firmware with the platform\'s firmware).');
    }
    final code = await dirs.runWithProfile('rpcs3', exePath, commandLine(file.path));
    if (code != 0 || !installed) {
      throw Ps3FirmwareException("RPCS3 couldn't install the firmware (exit code $code).");
    }
  }
}

final ps3FirmwareProvider = Provider<Ps3Firmware?>((ref) {
  final dirs = ref.watch(launchDirectoriesProvider);
  return dirs == null ? null : Ps3Firmware(ref.watch(appRootProvider), dirs);
});
