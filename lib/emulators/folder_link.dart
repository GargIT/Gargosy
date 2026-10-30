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
  String toString() =>
      "A folder link can't be made at $link: $cause. "
      'The drive may be FAT32 or exFAT, which have no links, or the folder may be in use.';
}

/// Makes the folder link [link] → [target] (a junction on Windows).
typedef LinkMaker = void Function(String link, String target);

void _makeLink(String link, String target) => io.Link(link).createSync(target);

/// Folders known this session to hold links ([_checkCanLink]), lower case.
final _canLinkIn = <String>{};

/// Forgets what [_checkCanLink] learned (tests).
@visibleForTesting
void resetLinkCheck() => _canLinkIn.clear();

/// What [pointFolderLink] did besides pointing the link.
class FolderLinkResult {
  const FolderLinkResult({this.movedToTemplate});

  /// Where a real folder (or file) that was where the link goes was moved:
  /// the profile's folder, the template, or set aside. Never deleted.
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
/// - A real folder in the way (an imported install with data in it, or a
///   release zip that ships the folder) is never deleted. It becomes the
///   profile's folder when that holds no files yet; otherwise it goes to
///   [templateDir] (`userdata\templates\<emu>\<folder>`, which new profiles
///   start from) the first time, and to [setAsideDir] after that.
/// - A file in the way is renamed `<name>.gargosy-off` (`… (2)` when taken).
///
/// Both paths go through [guard]: [link] must be in `emulators\`, [target]
/// in the active profile's folder. Throws [FolderLinkUnsupported] when the
/// drive has no links, before anything is moved (issue #49).
FolderLinkResult pointFolderLink({
  required String link,
  required String target,
  required PathGuard guard,
  required String templateDir,
  required String setAsideDir,
  LinkMaker makeLink = _makeLink,
}) {
  final linkPath = guard.check(link);
  final targetPath = guard.check(target);
  final root = guard.root;
  if (!guard.isWithin(root.emulators, linkPath)) {
    throw PathGuardException(linkPath, 'a folder link goes only in emulators\\');
  }
  final profile = guard.activeProfileId;
  if (profile == null || !guard.isWithin(p.join(root.profiles, profile), targetPath)) {
    throw PathGuardException(targetPath, "a folder link points only into the active profile's folder");
  }
  io.Directory(targetPath).createSync(recursive: true);

  String? moved;
  final inTheWay = io.FileSystemEntity.typeSync(linkPath, followLinks: false);
  // Something would be moved aside: first make sure a link can be made here,
  // so on a drive without links (FAT32, exFAT) nothing moves (issue #49).
  if (inTheWay != io.FileSystemEntityType.link && inTheWay != io.FileSystemEntityType.notFound) {
    _checkCanLink(linkPath, targetPath, guard, makeLink);
  }
  switch (inTheWay) {
    case io.FileSystemEntityType.link:
      if (_same(io.Link(linkPath).targetSync(), targetPath, guard)) return const FolderLinkResult();
      io.Link(linkPath).deleteSync(); // the link only, never what it points at
    case io.FileSystemEntityType.directory:
      if (!_hasFiles(targetPath)) {
        // The profile has nothing yet: the data is its own from here on.
        io.Directory(targetPath).deleteSync(recursive: true);
        io.Directory(linkPath).renameSync(targetPath);
        moved = targetPath;
        io.Directory(targetPath).createSync(recursive: true);
      } else {
        final template = guard.check(templateDir);
        moved = _moveAside(
          linkPath,
          io.FileSystemEntity.typeSync(template, followLinks: false) == io.FileSystemEntityType.notFound
              ? template
              : guard.check(setAsideDir),
        );
      }
      debugPrint('[FolderLink] $linkPath was a real folder: moved to $moved');
    case io.FileSystemEntityType.notFound:
      break;
    default:
      moved = _free(guard.check('$linkPath.gargosy-off'));
      io.File(linkPath).renameSync(moved);
  }

  try {
    makeLink(linkPath, targetPath);
  } on io.FileSystemException catch (e) {
    throw FolderLinkUnsupported(linkPath, e);
  }
  debugPrint('[FolderLink] $linkPath → $targetPath');
  return FolderLinkResult(movedToTemplate: moved);
}

/// Throws [FolderLinkUnsupported] unless a link can be made beside [linkPath]:
/// a test link to [targetPath], `.gargosy-linktest`, made and removed at once.
/// A folder that held one is remembered for the session.
void _checkCanLink(String linkPath, String targetPath, PathGuard guard, LinkMaker makeLink) {
  final dir = p.dirname(linkPath);
  if (_canLinkIn.contains(guard.pathKey(dir))) return;
  final probe = guard.check(p.join(dir, '.gargosy-linktest'));
  removeFolderLink(probe); // left by a check that didn't finish
  if (io.FileSystemEntity.typeSync(probe, followLinks: false) != io.FileSystemEntityType.notFound) {
    throw FolderLinkUnsupported(linkPath, 'something that is not a link is at $probe');
  }
  try {
    makeLink(probe, targetPath);
  } on io.FileSystemException catch (e) {
    throw FolderLinkUnsupported(linkPath, e);
  }
  removeFolderLink(probe);
  _canLinkIn.add(guard.pathKey(dir));
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

/// Whether a link's target [a] is [b], as the file system compares (#204).
bool _same(String a, String b, PathGuard guard) =>
    // Windows reports a junction's target with a \\?\ prefix.
    guard.samePath(a.replaceFirst(RegExp(r'^\\\\\?\\'), ''), b);

/// Moves the folder [from] to [to], or `<to> (2)`, `(3)` … when [to] is
/// taken: nothing is overwritten.
String _moveAside(String from, String to) {
  final dest = _free(to);
  io.Directory(p.dirname(dest)).createSync(recursive: true);
  io.Directory(from).renameSync(dest);
  return dest;
}

/// [path], or `<path> (2)`, `(3)` … : the first name nothing has.
String _free(String path) {
  var dest = path;
  for (var n = 2; io.FileSystemEntity.typeSync(dest, followLinks: false) != io.FileSystemEntityType.notFound; n++) {
    dest = '$path ($n)';
  }
  return dest;
}

/// Whether [dir] holds a file anywhere (empty folders don't count).
bool _hasFiles(String dir) {
  final d = io.Directory(dir);
  return d.existsSync() && d.listSync(recursive: true, followLinks: false).any((e) => e is! io.Directory);
}
