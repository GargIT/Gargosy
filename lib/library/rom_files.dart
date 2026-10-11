import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/romm/romm_models.dart';
import '../profiles/app_root.dart';
import '../profiles/path_guard.dart';

/// Where a game's ROM lives: `roms\<platform>\<fs_name>`, a file for a single
/// file game and a folder for a multi-file one. The ROM folders hold only ROMs.
class RomFiles {
  RomFiles(this.root);

  final AppRoot root;

  // `!` is included, as everywhere Gargosy builds a ROM name (CLAUDE.md).
  static final _unsafe = RegExp(r'[<>:"/\\|?*!\x00-\x1F]');

  /// [name] as one safe Windows path segment.
  static String safeName(String name) {
    final cleaned = name.replaceAll(_unsafe, '_').trim().replaceAll(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? '_' : cleaned;
  }

  String platformDir(Game g) => p.join(root.roms, safeName(g.platformSlug ?? 'unknown'));

  String _plainPath(Game g) => p.join(platformDir(g), safeName(g.fsName ?? g.fileName ?? g.name));

  /// Where a `.zip` game sits once unpacked for an emulator that can't read
  /// zips (`RomPreparer`): a folder named without `.zip`. Null for other games.
  String? unpackedDirFor(Game g) {
    final plain = _plainPath(g);
    if (p.extension(plain).toLowerCase() != '.zip') return null;
    return p.join(platformDir(g), safeName(p.basenameWithoutExtension(plain)));
  }

  /// The game on this PC: its file or folder, or for a zip game that was
  /// unpacked, that folder. Where a download goes when it's on neither.
  String pathFor(Game g) {
    final plain = _plainPath(g);
    if (io.FileSystemEntity.typeSync(plain) == io.FileSystemEntityType.notFound) {
      final unpacked = unpackedDirFor(g);
      if (unpacked != null && io.Directory(unpacked).existsSync()) return unpacked;
    }
    return plain;
  }

  bool isDownloaded(Game g) {
    final path = pathFor(g);
    return io.File(path).existsSync() || io.Directory(path).existsSync();
  }

  Future<void> delete(Game g, PathGuard guard) async {
    final path = guard.check(pathFor(g));
    if (io.File(path).existsSync()) {
      await io.File(path).delete();
    } else if (io.Directory(path).existsSync()) {
      await io.Directory(path).delete(recursive: true);
    }
  }
}
