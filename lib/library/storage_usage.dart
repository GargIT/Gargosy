import 'dart:io' as io;
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../profiles/app_root.dart';

/// One file or folder in a platform's ROM folder: a game on this PC.
class RomEntry {
  const RomEntry({required this.path, required this.bytes, required this.modified});

  final String path;
  final int bytes;
  final DateTime modified;

  String get name => p.basename(path);
}

/// A platform's folder in `roms\`, its games largest first.
class PlatformUsage {
  const PlatformUsage({required this.folder, required this.entries});

  /// The folder's name: RomM's platform slug.
  final String folder;
  final List<RomEntry> entries;

  int get bytes => entries.fold(0, (n, e) => n + e.bytes);
}

/// What Gargosy's folders take on this PC (Settings → Storage, #145).
class StorageUsage {
  const StorageUsage({required this.folders, required this.platforms});

  /// By label, in the order shown: ROMs, Emulators, …
  final Map<String, int> folders;

  /// Largest first.
  final List<PlatformUsage> platforms;
}

/// The bytes under [path], a file or a folder. Links (the emulators' folder
/// junctions to a profile) aren't followed, so nothing is counted twice.
int sizeOf(String path) {
  final type = io.FileSystemEntity.typeSync(path, followLinks: false);
  if (type == io.FileSystemEntityType.file) return io.File(path).lengthSync();
  if (type != io.FileSystemEntityType.directory) return 0;
  var n = 0;
  try {
    for (final e in io.Directory(path).listSync(recursive: true, followLinks: false)) {
      if (e is io.File) {
        try {
          n += e.lengthSync();
        } on io.FileSystemException {
          // In use or gone: left out.
        }
      }
    }
  } on io.FileSystemException {
    // A folder that can't be read counts what was read.
  }
  return n;
}

/// The games in one platform's folder, largest first.
List<RomEntry> romsIn(String dir) {
  if (!io.Directory(dir).existsSync()) return const [];
  return [
    for (final e in io.Directory(dir).listSync(followLinks: false))
      if (e is io.File || e is io.Directory)
        RomEntry(path: e.path, bytes: sizeOf(e.path), modified: e.statSync().modified),
  ]..sort((a, b) => b.bytes.compareTo(a.bytes));
}

/// Reads [root]'s folders off the UI isolate (`roms\` can be hundreds of GB).
Future<StorageUsage> readStorage(AppRoot root) {
  final r = root.root;
  return Isolate.run(() {
    final at = AppRoot(r);
    final platforms = [
      if (io.Directory(at.roms).existsSync())
        for (final d in io.Directory(at.roms).listSync(followLinks: false).whereType<io.Directory>())
          PlatformUsage(folder: p.basename(d.path), entries: romsIn(d.path)),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
    final roms = platforms.fold(0, (n, x) => n + x.bytes);
    return StorageUsage(
      folders: {
        'ROMs': roms,
        'Emulators': sizeOf(at.emulators),
        'BIOS': sizeOf(at.bios),
        "Profiles' saves, backups and emulator data": sizeOf(at.profiles),
        'Image cache': sizeOf(p.join(at.appData, 'cache', 'images')),
        'Temp': sizeOf(p.join(at.appData, 'temp')),
      },
      platforms: platforms,
    );
  });
}
