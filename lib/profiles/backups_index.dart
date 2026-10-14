import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'profile_paths.dart';

/// The Hive box that lists a profile's backups. Its file, `<name>.hive`,
/// sits in the profile's `backups\` beside the zips it lists. The name stays
/// unique per profile because Hive finds an open box by name alone.
String backupsBoxName(String profileId) => 'backups_${profileId.replaceAll('-', '_')}';

/// Makes `backups\` and moves the box there from the profile's root, where
/// Gargosy kept it before (with Hive's compaction copy, `.hivec`, when a
/// crash left one). A leftover lock from a crash goes. A box already in
/// `backups\` is never replaced. Runs before the box opens, and returns the
/// folder to open it in: `backups\`, or the profile's root when the box
/// couldn't be moved (it opens where it is then, and moves on a later start).
String moveBackupsIndex(ProfilePaths paths) {
  final name = backupsBoxName(paths.id);
  io.File inRoot(String ext) => io.File(paths.guard.check(p.join(paths.dir, '$name.$ext')));
  String inBackups(String ext) => paths.guard.check(p.join(paths.backups, '$name.$ext'));
  try {
    io.Directory(paths.guard.check(paths.backups)).createSync(recursive: true);
    if (!io.File(inBackups('hive')).existsSync()) {
      for (final ext in const ['hivec', 'hive']) {
        final f = inRoot(ext);
        if (f.existsSync()) f.renameSync(inBackups(ext));
      }
    }
    final lock = inRoot('lock');
    if (lock.existsSync() && !inRoot('hive').existsSync()) lock.deleteSync();
  } on io.FileSystemException catch (e) {
    debugPrint('[Backups] the backup list stays in the profile folder for now: $e');
  }
  return inRoot('hive').existsSync() && !io.File(inBackups('hive')).existsSync() ? paths.dir : paths.backups;
}
