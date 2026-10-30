import 'dart:io' as io;
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/romm/romm_models.dart';
import '../profiles/path_guard.dart';
import 'disk_space.dart';
import 'download_check.dart';
import 'rom_files.dart';
import '../l10n/tr.dart';

enum DownloadPhase {
  /// Waiting for the downloads before it (#143).
  queued,
  downloading,

  /// Checked against RomM's hashes (#225).
  checking,
  extracting,
  done,
  failed,
  cancelled;

  /// Waiting or running: not yet on this PC, and not to be started again.
  bool get active => this == queued || this == downloading || this == checking || this == extracting;
}

class DownloadProgress {
  const DownloadProgress(this.phase, {this.received = 0, this.total = 0, this.error});

  final DownloadPhase phase;
  final int received;
  final int total;
  final String? error;

  double? get fraction => total > 0 ? (received / total).clamp(0, 1).toDouble() : null;
}

/// How RomM sends a game's content (`/api/roms/{id}/content`): one file as it
/// is, more than one as a zip of the game's folder.
enum _Shape {
  /// One file at the top: `roms\<platform>\<fs_name>`.
  file,

  /// One file inside the game's folder: `roms\<platform>\<fs_name>\<file_name>`.
  fileInFolder,

  /// A zip, unpacked into `roms\<platform>\<fs_name>\`.
  zip,
}

/// Downloads a game's ROM from RomM into `roms\` (spec §2). The file is staged
/// in `userdata\app\temp` and only moved into `roms\` when complete, so `roms\`
/// never holds a partial download. A single file is kept as is, even when it
/// is a zip (arcade sets).
class DownloadService {
  DownloadService({
    required this.dio,
    required this.auth,
    required this.files,
    required this.guard,
    required this.tempDir,
    required this.urlFor,
    this.detail,
    this.disk,
    this.checkHashes = _always,
  });

  static bool _always() => true;

  final Dio dio;
  final Options Function() auth;
  final RomFiles files;
  final PathGuard guard;
  final String tempDir;
  final String Function(Game) urlFor;

  /// The game with its file list (list pages leave it out).
  final Future<Game?> Function(String id)? detail;

  /// The free space on a path's volume (#142); null skips the check.
  final DiskInfo? disk;

  /// Whether a download is checked against RomM's hashes before it moves
  /// into `roms\` (#225; Settings → Storage → Check downloads).
  final bool Function() checkHashes;

  /// What [download] writes, by place: the download in temp, a zip's
  /// unpacked copy beside it, and the game in `roms\` when that's another
  /// drive (on the same one it's only renamed).
  static Map<String, int> spaceFor({
    required int size,
    required bool zip,
    required String part,
    required String staging,
    required String target,
    required DiskInfo disk,
  }) => {part: size, if (zip) staging: size, if (disk.volumeOf(target) != disk.volumeOf(part)) target: size};

  /// What RomM will send for [game], and the file's name when it sits in the
  /// game's folder.
  Future<({_Shape shape, String? fileName, List<RomFileHashes> hashes})> _shapeOf(Game game) async {
    var list = game.files;
    if (list.isEmpty && detail != null) list = (await detail!(game.id))?.files ?? const [];
    final hashes = [for (final f in list) ?RomFileHashes.fromJson(f, folder: game.fsName)];
    if (list.isEmpty) return (shape: game.isMultiFile ? _Shape.zip : _Shape.file, fileName: null, hashes: hashes);
    if (list.length > 1) return (shape: _Shape.zip, fileName: null, hashes: hashes);
    final name = list.single['file_name']?.toString();
    if (name != null && name.isNotEmpty && name != game.fsName) {
      return (shape: _Shape.fileInFolder, fileName: RomFiles.safeName(name), hashes: hashes);
    }
    return (shape: _Shape.file, fileName: null, hashes: hashes);
  }

  Future<void> download(Game game, {void Function(DownloadProgress)? onProgress, CancelToken? cancel}) async {
    final target = guard.check(files.pathFor(game));
    final (:shape, :fileName, :hashes) = await _shapeOf(game);
    final check = checkHashes() && hashes.any((h) => h.hasAny);
    await io.Directory(guard.check(tempDir)).create(recursive: true);
    final part = guard.check(p.join(tempDir, 'download-${game.id}.part'));
    final staging = guard.check(p.join(tempDir, 'extract-${game.id}'));
    if (disk case final disk?) {
      checkSpace(
        spaceFor(
          size: game.fileSize,
          zip: shape == _Shape.zip,
          part: part,
          staging: staging,
          target: target,
          disk: disk,
        ),
        disk,
      );
    }
    try {
      await dio.download(
        urlFor(game),
        part,
        options: auth(),
        cancelToken: cancel,
        deleteOnError: true,
        onReceiveProgress: (received, total) => onProgress?.call(
          DownloadProgress(DownloadPhase.downloading, received: received, total: total > 0 ? total : game.fileSize),
        ),
      );
      // One file: checked before anything moves (#225).
      // A ROM that is an archive RomM hashed by what's inside: not checked.
      final archive = archiveExtensions.contains(p.extension(fileName ?? game.fsName ?? '').toLowerCase());
      // Checking: all of it is here already, so the space math counts none still to come.
      final size = io.File(part).lengthSync();
      final checking = DownloadProgress(DownloadPhase.checking, received: size, total: size);
      if (check && shape != _Shape.zip && hashes.length == 1 && !archive) {
        onProgress?.call(checking);
        if (!await fileMatches(part, hashes.single)) throw DownloadDamaged([hashes.single.name]);
      }
      await io.Directory(guard.check(p.dirname(target))).create(recursive: true);
      switch (shape) {
        case _Shape.zip:
          onProgress?.call(const DownloadProgress(DownloadPhase.extracting));
          // Multi-GB discs: unpacked off the UI isolate so the app keeps responding.
          await _unzipOffIsolate(part, staging, guard);
          // Several files: each checked once unpacked, before the folder moves.
          if (check) {
            onProgress?.call(checking);
            final damaged = await damagedIn(staging, hashes);
            if (damaged.isNotEmpty) throw DownloadDamaged(damaged);
          }
          _replace(target);
          io.Directory(staging).renameSync(target);
        case _Shape.fileInFolder:
          io.Directory(staging).createSync(recursive: true);
          _move(part, guard.join(staging, fileName!));
          _replace(target);
          io.Directory(staging).renameSync(target);
        case _Shape.file:
          _replace(target);
          _move(part, target);
      }
      onProgress?.call(const DownloadProgress(DownloadPhase.done));
    } finally {
      if (io.File(part).existsSync()) io.File(part).deleteSync();
      if (io.Directory(staging).existsSync()) io.Directory(staging).deleteSync(recursive: true);
    }
  }

  void _replace(String target) {
    if (io.File(target).existsSync()) io.File(target).deleteSync();
    if (io.Directory(target).existsSync()) io.Directory(target).deleteSync(recursive: true);
  }

  void _move(String from, String to) {
    try {
      io.File(from).renameSync(to);
    } on io.FileSystemException {
      io.File(from).copySync(to); // another drive
      io.File(from).deleteSync();
    }
  }
}

/// Unpacks [zip] into [dir]; an entry whose name escapes [dir] stops it.
/// Top-level so it can run in another isolate.
/// [unzipInto] in another isolate. Top-level, so the closure sent there
/// holds only these three: one made inside [DownloadService.download] takes
/// its whole scope along (the cancel token, the progress listener), which
/// an isolate can't receive.
Future<void> _unzipOffIsolate(String zip, String dir, PathGuard guard) => Isolate.run(() => unzipInto(zip, dir, guard));

void unzipInto(String zip, String dir, PathGuard guard) {
  final input = InputFileStream(zip);
  try {
    final archive = ZipDecoder().decodeStream(input);
    for (final entry in archive) {
      final out = guard.join(dir, entry.name);
      if (!p.isWithin(dir, out)) throw PathGuardException(entry.name, tr('outside the game folder'));
      if (!entry.isFile) {
        io.Directory(out).createSync(recursive: true);
        continue;
      }
      io.Directory(p.dirname(out)).createSync(recursive: true);
      final output = OutputFileStream(out);
      try {
        entry.writeContent(output);
      } finally {
        output.closeSync();
      }
    }
  } finally {
    input.closeSync();
  }
}
