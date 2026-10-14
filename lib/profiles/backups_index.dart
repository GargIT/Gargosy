import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'profile_paths.dart';

/// The Hive box that lists a profile's backups: `backups\index.hive`,
/// beside the zips it lists. Every profile's box has this name, and Hive
/// finds a box by name alone (also one still opening), so only one is ever
/// open: every open and close below runs after the one before has finished.
/// No other box in Gargosy may be called `index`.
const backupsBoxName = 'index';

/// The box opened last and not closed since. Hive's own registry is
/// process-wide too; this only says which profile's box that is.
Box<List>? _open;
Future<void> _queue = Future.value();

/// Runs [step] after every open and close before it. A failure is returned
/// to the caller only: the next step still runs.
Future<T> _inTurn<T>(Future<T> Function() step) {
  final result = _queue.then((_) => step());
  _queue = result.then((_) {}, onError: (Object e) => debugPrint('[Backups] $e'));
  return result;
}

/// Opens [paths]' backup list, after closing the one open before (another
/// profile's), so Hive never hands this profile that box.
Future<Box<List>> openBackupsBox(ProfilePaths paths) => _inTurn(() async {
      final before = _open;
      _open = null;
      if (before != null && before.isOpen) await before.close();
      io.Directory(paths.guard.check(paths.backups)).createSync(recursive: true);
      return _open = await Hive.openBox<List>(backupsBoxName, path: paths.backups);
    });

/// Closes [box], or with none the open backup list, once the opens and
/// closes before it are done (a list still opening is closed too).
Future<void> closeBackupsBox([Box<List>? box]) => _inTurn(() async {
      final closing = box ?? _open;
      if (identical(closing, _open)) _open = null;
      if (closing != null && closing.isOpen) await closing.close();
    });
