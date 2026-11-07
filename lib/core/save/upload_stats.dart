import 'dart:io' as io;

/// The newest change and the size of what a push uploads (#294): files by
/// themselves, folders by every file inside (links not followed). Null when
/// nothing can be read.
Future<({DateTime newest, int bytes})?> uploadStats(Iterable<io.File> entries) async {
  DateTime? newest;
  var bytes = 0;
  void count(io.FileStat stat) {
    if (newest == null || stat.modified.isAfter(newest!)) newest = stat.modified;
    bytes += stat.size;
  }

  for (final entry in entries) {
    try {
      if (await io.FileSystemEntity.isDirectory(entry.path)) {
        await for (final f in io.Directory(entry.path).list(recursive: true, followLinks: false)) {
          if (f is! io.File) continue;
          final stat = await f.stat();
          // A locked or vanished file is left out, the rest still counted.
          if (stat.type != io.FileSystemEntityType.notFound) count(stat);
        }
      } else {
        final stat = await entry.stat();
        if (stat.type != io.FileSystemEntityType.notFound) count(stat);
      }
    } on io.FileSystemException {
      // Gone or locked: left out.
    }
  }
  final at = newest;
  return at == null ? null : (newest: at, bytes: bytes);
}
