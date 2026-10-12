import 'package:path/path.dart' as p;

import '../profiles/app_root.dart';

/// Where an update stages: `userdata\app\update\` (issue #16).
class UpdatePaths {
  UpdatePaths(this.root);

  final AppRoot root;

  String get dir => p.join(root.appData, 'update');

  /// The downloaded zip, kept until the next start after the update.
  String zip(String version) => p.join(dir, 'Gargosy-$version.zip');

  /// The new version, unpacked: what the updater copies into the root.
  String get unpacked => p.join(dir, 'Gargosy');

  /// The old app files, moved aside by the updater (put back if it fails).
  String get previous => p.join(dir, 'previous');

  /// The updater's copy that runs, so the one beside Gargosy.exe can be replaced.
  String get updaterCopy => p.join(dir, updaterExe);

  String get log => p.join(dir, 'update.log');

  static const updaterExe = 'GargosyUpdate.exe';

  /// The updater beside the running Gargosy.exe.
  String get installedUpdater => p.join(root.root, updaterExe);
}
