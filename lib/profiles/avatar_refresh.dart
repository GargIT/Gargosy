import 'dart:io' as io;
import 'dart:typed_data';

import '../core/romm/romm_auth_client.dart';
import 'json_file.dart';
import 'login_store.dart';
import 'profile.dart';
import 'profile_paths.dart';
import 'profile_store.dart';

/// Brings [profile]'s badge picture up to date with the avatar on RomM, which
/// the user may have added or changed after the profile was made. Returns the
/// updated profile when something changed, else null. Never removes a picture:
/// no avatar (or an unreachable server) leaves the profile as it is.
Future<Profile?> refreshAvatar({
  required Profile profile,
  required ProfileLogin login,
  required RommAuth auth,
  required ProfileStore store,
  required ProfilePaths paths,
}) async {
  final bytes = await auth.fetchAvatar(login.token, profile.rommUserId);
  if (bytes == null || !looksLikeImage(bytes)) return null;
  final file = io.File(paths.avatarFile);
  if (profile.hasAvatar && file.existsSync() && _same(file.readAsBytesSync(), bytes)) return null;
  await writeBytesAtomic(paths.guard, paths.avatarFile, bytes);
  final updated = profile.copyWith(hasAvatar: true);
  await store.save(updated);
  return updated;
}

/// PNG, JPEG, GIF or WebP, by their first bytes (a web page is not a picture).
bool looksLikeImage(Uint8List b) {
  bool starts(List<int> sig, [int at = 0]) {
    if (b.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[at + i] != sig[i]) return false;
    }
    return true;
  }

  return starts([0x89, 0x50, 0x4E, 0x47]) ||
      starts([0xFF, 0xD8, 0xFF]) ||
      starts('GIF8'.codeUnits) ||
      (starts('RIFF'.codeUnits) && starts('WEBP'.codeUnits, 8));
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
