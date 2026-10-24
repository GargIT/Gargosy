import 'dart:io' as io;
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/romm/romm_models.dart';
import '../profiles/path_guard.dart';
import 'disk_space.dart';
import 'rom_files.dart';

enum DownloadPhase { downloading, extracting, done, failed, cancelled }

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
    this.freeSpace,
  });

  final Dio dio;
  final Options Function() auth;
  final RomFiles files;
  final PathGuard guard;
  final String tempDir;
  final String Function(Game) urlFor;

  /// The game with its file list (list pages leave it out).
  final Future<Game?> Function(String id)? detail;

  /// The free space on a path's drive (#142); null skips the check.
  final FreeSpaceOf? freeSpace;

  /// What [download] writes, by place: the download in temp, a zip's
  /// unpacked copy beside it, and the game in `roms\` when that's another
  /// drive (on the same one it's only renamed).
  static Map<String, int> spaceFor({
    required int size,
    required bool zip,
    required String part,
    required String staging,
    required String target,
  }) => {
    part: size,
    if (zip) staging: size,
    if (driveOf(target).toUpperCase() != driveOf(part).toUpperCase()) target: size,
  };

  /// What RomM will send for [game], and the file's name when it sits in the
  /// game's folder.
  Future<({_Shape shape, String? fileName})> _shapeOf(Game game) async {
    var list = game.files;
    if (list.isEmpty && detail != null) list = (await detail!(game.id))?.files ?? const [];
    if (list.isEmpty) return (shape: game.isMultiFile ? _Shape.zip : _Shape.file, fileName: null);
    if (list.length > 1) return (shape: _Shape.zip, fileName: null);
    final name = list.single['file_name']?.toString();
    if (name != null && name.isNotEmpty && name != game.fsName) {
      return (shape: _Shape.fileInFolder, fileName: RomFiles.safeName(name));
    }
    return (shape: _Shape.file, fileName: null);
  }

  Future<void> download(Game game, {void Function(DownloadProgress)? onProgress, CancelToken? cancel}) async {
    final target = guard.check(files.pathFor(game));
    final (:shape, :fileName) = await _shapeOf(game);
    await io.Directory(guard.check(tempDir)).create(recursive: true);
    final part = guard.check(p.join(tempDir, 'download-${game.id}.part'));
    final staging = guard.check(p.join(tempDir, 'extract-${game.id}'));
    if (freeSpace case final free?) {
      checkSpace(
        spaceFor(size: game.fileSize, zip: shape == _Shape.zip, part: part, staging: staging, target: target),
        free,
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
      await io.Directory(guard.check(p.dirname(target))).create(recursive: true);
      switch (shape) {
        case _Shape.zip:
          onProgress?.call(const DownloadProgress(DownloadPhase.extracting));
          // Multi-GB discs: unpacked off the UI isolate so the app keeps responding.
          await _unzipOffIsolate(part, staging, guard);
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
      if (!p.isWithin(dir, out)) throw PathGuardException(entry.name, 'outside the game folder');
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
