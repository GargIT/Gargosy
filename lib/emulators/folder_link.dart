import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../profiles/path_guard.dart';

/// The drive can't hold a folder link (FAT32, exFAT): the emulator can't be
/// pointed at a profile there.
class FolderLinkUnsupported implements Exception {
  const FolderLinkUnsupported(this.link, this.cause);
  final String link;
  final Object cause;

  @override
  String toString() => "A folder link can't be made at $link (the drive may be FAT32 or exFAT): $cause";
}

/// What [pointFolderLink] did besides pointing the link.
class FolderLinkResult {
  const FolderLinkResult({this.movedToTemplate});

  /// A real folder that was where the link goes, moved here (never deleted).
  final String? movedToTemplate;
}

/// Points [link] (a folder next to an emulator's exe in `emulators\`, such as
/// Eden's `user\`) at [target] (that folder in the active profile), issue #8.
/// On Windows it's a directory junction: no admin rights, any NTFS drive,
/// and the emulator writes straight into the profile. Only one emulator runs
/// at a time, so re-pointing it per launch is safe.
///
/// - [target] is made when missing.
/// - A link to anywhere else is re-pointed.
/// - A real folder in the way (an imported install with data in it) is moved
///   once into [templateDir] (`userdata\templates\<emu>\<folder>`), never
///   deleted; a file in the way is renamed `<name>.gargosy-off`.
///
/// Both paths go through [guard]: [link] must be in `emulators\`, [target]
/// in the active profile's folder. Throws [FolderLinkUnsupported] when the
/// drive has no links.
FolderLinkResult pointFolderLink({
  required String link,
  required String target,
  required PathGuard guard,
  required String templateDir,
}) {
  final linkPath = guard.check(link);
  final targetPath = guard.check(target);
  final root = guard.root;
  if (!p.isWithin(root.emulators, linkPath)) {
    throw PathGuardException(linkPath, 'a folder link goes only in emulators\\');
  }
  final profile = guard.activeProfileId;
  if (profile == null || !p.isWithin(p.join(root.profiles, profile), targetPath)) {
    throw PathGuardException(targetPath, "a folder link points only into the active profile's folder");
  }
  io.Directory(targetPath).createSync(recursive: true);

  String? moved;
  switch (io.FileSystemEntity.typeSync(linkPath, followLinks: false)) {
    case io.FileSystemEntityType.link:
      if (_same(io.Link(linkPath).targetSync(), targetPath)) return const FolderLinkResult();
      io.Link(linkPath).deleteSync(); // the link only, never what it points at
    case io.FileSystemEntityType.directory:
      moved = _moveAside(linkPath, guard.check(templateDir));
      debugPrint('[FolderLink] $linkPath was a real folder: moved to $moved');
    case io.FileSystemEntityType.notFound:
      break;
    default:
      final off = guard.check('$linkPath.gargosy-off');
      io.File(linkPath).renameSync(off);
      moved = off;
  }

  try {
    io.Link(linkPath).createSync(targetPath);
  } on io.FileSystemException catch (e) {
    throw FolderLinkUnsupported(linkPath, e);
  }
  debugPrint('[FolderLink] $linkPath → $targetPath');
  return FolderLinkResult(movedToTemplate: moved);
}

/// Removes [path] when it's a folder link (the link, never its target).
/// True when there was one.
bool removeFolderLink(String path) {
  if (!isFolderLink(path)) return false;
  io.Link(path).deleteSync();
  return true;
}

/// Whether [path] itself is a link (a junction on Windows), whatever it points at.
bool isFolderLink(String path) =>
    io.FileSystemEntity.typeSync(path, followLinks: false) == io.FileSystemEntityType.link;

/// Removes every folder link under [dir] (an emulator's install), without
/// following any: before the install is deleted or updated, so neither can
/// reach a profile's data. The number removed.
int removeFolderLinksIn(String dir) {
  final d = io.Directory(dir);
  if (!d.existsSync() || isFolderLink(dir)) return 0;
  var n = 0;
  for (final e in d.listSync(recursive: true, followLinks: false)) {
    if (e is io.Link) {
      e.deleteSync();
      n++;
    }
  }
  return n;
}

bool _same(String a, String b) {
  String norm(String s) => p.normalize(p.absolute(s)).toLowerCase().replaceAll(RegExp(r'[\\/]+$'), '');
  // Windows reports a junction's target with a \\?\ prefix.
  return norm(a.replaceFirst(RegExp(r'^\\\\\?\\'), '')) == norm(b);
}

/// Moves the folder [from] to [to], or `<to> (2)`, `(3)` … when [to] is
/// taken: nothing is overwritten.
String _moveAside(String from, String to) {
  var dest = to;
  for (var n = 2; io.FileSystemEntity.typeSync(dest, followLinks: false) != io.FileSystemEntityType.notFound; n++) {
    dest = '$to ($n)';
  }
  io.Directory(p.dirname(dest)).createSync(recursive: true);
  io.Directory(from).renameSync(dest);
  return dest;
}
