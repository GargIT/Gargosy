import 'package:path/path.dart' as p;

import 'app_root.dart';
import 'path_guard.dart';

/// Where one profile's files live (spec §3).
class ProfilePaths {
  ProfilePaths(this.root, this.id) {
    if (!PathGuard.isProfileId(id)) throw ArgumentError.value(id, 'id', 'not a profile id');
  }

  static final _emulatorId = RegExp(r'^[a-z0-9_-]{1,40}$');

  final AppRoot root;
  final String id;

  String get dir => p.join(root.profiles, id);
  String get profileFile => p.join(dir, 'profile.json');
  String get prefsFile => p.join(dir, 'prefs.json');
  String get avatarFile => p.join(dir, 'avatar.png');
  String get emulatorsDir => p.join(dir, 'emulators');
  String get backups => p.join(dir, 'backups');
  String get cache => p.join(dir, 'cache');

  String emulatorDir(String emulatorId) {
    if (!_emulatorId.hasMatch(emulatorId)) throw ArgumentError.value(emulatorId, 'emulatorId');
    return p.join(emulatorsDir, emulatorId);
  }

  /// A guard that allows this profile's folder (and the shared ones).
  PathGuard get guard => PathGuard(root, activeProfileId: id);
}
