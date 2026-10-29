import 'dart:typed_data';

import '../platform/platform_info.dart';
import 'dpapi.dart';

/// Encrypts secrets (the RomM token, RetroAchievements' Connect token) so
/// only this PC's user can read them back (#198). Windows' is DPAPI.
abstract class SecretStore {
  Uint8List protect(Uint8List data);

  /// Null when the data can't be decrypted (another user or PC, or damaged).
  Uint8List? unprotect(Uint8List data);

  /// The id of the PC the secrets are bound to, or null if it can't be read.
  /// Login files are named after it (`PcIdentity`).
  String? machineId();
}

/// The [SecretStore] of [platform]'s OS.
SecretStore secretStoreFor(PlatformInfo platform) {
  if (platform.isWindows) return DpapiSecretStore();
  throw UnsupportedError('No secret store on ${platform.os} yet');
}
