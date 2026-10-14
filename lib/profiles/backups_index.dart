import 'dart:io' as io;

import 'package:hive/hive.dart';

import 'profile_paths.dart';

/// The Hive box that lists a profile's backups: `backups\index.hive`,
/// beside the zips it lists. Every profile's box has this name, so only one
/// is ever open ([openBackupsBox]).
const backupsBoxName = 'index';

Box<List>? _open;
Future<void> _closing = Future.value();

/// Opens [paths]' backup list. Hive finds an open box by name alone, so the
/// box open before (another profile's) is closed first, and the open waits
/// until every close has finished: Hive never hands this profile that box.
Future<Box<List>> openBackupsBox(ProfilePaths paths) async {
  await closeBackupsBox();
  io.Directory(paths.guard.check(paths.backups)).createSync(recursive: true);
  return _open = await Hive.openBox<List>(backupsBoxName, path: paths.backups);
}

/// Closes the open backup list ([box] only, when given) and waits for it;
/// the next [openBackupsBox] waits too.
Future<void> closeBackupsBox([Box<List>? box]) {
  final closing = _open;
  if (closing != null && (box == null || identical(box, closing))) {
    _open = null;
    _closing = Future.wait([_closing, closing.close()]);
  } else if (box != null) {
    _closing = Future.wait([_closing, box.close()]);
  }
  return _closing;
}
