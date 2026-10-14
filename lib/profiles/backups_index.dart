import 'dart:io' as io;

import 'package:path/path.dart' as p;

import 'profile_paths.dart';

/// The Hive box that lists a profile's backups. Its file, `<name>.hive`,
/// sits in the profile's `backups\` beside the zips it lists. The name stays
/// unique per profile because Hive finds an open box by name alone.
String backupsBoxName(String profileId) => 'backups_${profileId.replaceAll('-', '_')}';

/// Makes `backups\` and moves the box there from the profile's root, where
/// Gargosy kept it before. A leftover lock from a crash goes with it, and a
/// box already in `backups\` is never replaced. Runs before the box opens.
void moveBackupsIndex(ProfilePaths paths) {
  final name = backupsBoxName(paths.id);
  io.Directory(paths.guard.check(paths.backups)).createSync(recursive: true);
  final old = io.File(paths.guard.check(p.join(paths.dir, '$name.hive')));
  final moved = p.join(paths.backups, '$name.hive');
  if (old.existsSync() && !io.File(moved).existsSync()) old.renameSync(paths.guard.check(moved));
  final lock = io.File(paths.guard.check(p.join(paths.dir, '$name.lock')));
  if (lock.existsSync() && !old.existsSync()) lock.deleteSync();
}
