import 'dart:io' as io;
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../profiles/app_root.dart';
import '../profiles/path_guard.dart';
import 'app_files.dart';
import 'update_checker.dart';
import 'update_paths.dart';

/// Why a download can't be used; the UI shows [message] and nothing was replaced.
class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Downloads a release's zip into `userdata\app\update\` through
/// [PathGuard], checks it and unpacks it (issue #16). Nothing in the Gargosy
/// folder changes here: `GargosyUpdate.exe` does the swap after Gargosy exits.
class UpdateDownloader {
  UpdateDownloader({required this._dio, required AppRoot root})
      : _paths = UpdatePaths(root),
        _guard = PathGuard(root);

  final Dio _dio;
  final UpdatePaths _paths;
  final PathGuard _guard;

  UpdatePaths get paths => _paths;

  /// Downloads, checks and unpacks [release]; returns the unpacked
  /// `Gargosy\` folder. A cancel or a failed check leaves no zip and no
  /// unpacked folder behind. Throws [UpdateDownloadException], or Dio's
  /// cancel ([DioExceptionType.cancel]).
  Future<String> download(ReleaseInfo release,
      {void Function(int received, int total)? onProgress, CancelToken? cancel}) async {
    final dir = _guard.check(_paths.dir);
    await io.Directory(dir).create(recursive: true);
    final zip = _guard.check(_paths.zip(release.version.toString()));
    final part = _guard.check('$zip.part');
    final unpacked = _guard.check(_paths.unpacked);
    _deleteAll([zip, part, unpacked]);
    try {
      try {
        await _dio.download(
          release.assetUrl,
          part,
          cancelToken: cancel,
          deleteOnError: true,
          options: Options(followRedirects: true, receiveTimeout: const Duration(seconds: 60)),
          onReceiveProgress: (received, total) => onProgress?.call(received, total > 0 ? total : release.size),
        );
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        throw UpdateDownloadException("The download didn't finish: ${e.message ?? e.type.name}");
      }
      io.File(part).renameSync(zip);

      final size = io.File(zip).lengthSync();
      if (size != release.size) {
        throw UpdateDownloadException('The download is $size bytes, but GitHub says ${release.size}.');
      }
      final expected = release.sha256;
      if (expected != null) {
        final actual = (await sha256.bind(io.File(zip).openRead()).first).toString();
        if (actual != expected.toLowerCase()) {
          throw const UpdateDownloadException("The download doesn't match GitHub's checksum (SHA-256).");
        }
      }

      final error = await _unpackInIsolate(zip, unpacked, _guard);
      if (error != null) throw UpdateDownloadException(error);
      return unpacked;
    } catch (_) {
      _deleteAll([zip, part, unpacked]);
      rethrow;
    }
  }

  void _deleteAll(List<String> paths) {
    for (final path in paths) {
      try {
        final type = io.FileSystemEntity.typeSync(path);
        if (type == io.FileSystemEntityType.directory) {
          io.Directory(path).deleteSync(recursive: true);
        } else if (type != io.FileSystemEntityType.notFound) {
          io.File(path).deleteSync();
        }
      } on io.FileSystemException {
        // Left for the next try, which deletes it first.
      }
    }
  }
}

/// [unpackUpdate] off the UI isolate. Its own function, so the closure sent
/// to the isolate holds only these three (not the caller's async state).
Future<String?> _unpackInIsolate(String zip, String dir, PathGuard guard) =>
    Isolate.run(() => unpackUpdate(zip, dir, guard));

/// Unpacks the release [zip] (it holds `Gargosy\…`) into [dir] without the
/// top folder, then checks the layout: `Gargosy.exe`, `app-files.txt`, and
/// every listed file present. Returns why it can't be used, or null.
/// Entries in the user's folders (`roms\`, `userdata\` …; the zip has them
/// empty) are never unpacked. Top-level so it can run in another isolate.
String? unpackUpdate(String zip, String dir, PathGuard guard) {
  final input = InputFileStream(zip);
  try {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } on Object {
      return "The download isn't a zip that can be read.";
    }
    io.Directory(dir).createSync(recursive: true);
    for (final entry in archive) {
      final parts = entry.name.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty || parts.first != 'Gargosy') return "The zip isn't a Gargosy release (${entry.name}).";
      if (parts.length == 1 || AppFiles.protected.contains(parts[1].toLowerCase())) continue;
      final out = guard.join(dir, parts.skip(1).join('/'));
      if (!p.isWithin(dir, out)) return 'The zip has a path outside its folder (${entry.name}).';
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
  } on PathGuardException catch (e) {
    return 'The zip has a path that is not allowed (${e.path}).';
  } finally {
    input.closeSync();
  }

  if (!io.File(p.join(dir, 'Gargosy.exe')).existsSync()) return 'The zip has no Gargosy.exe.';
  final list = io.File(p.join(dir, AppFiles.fileName));
  if (!list.existsSync()) return 'The zip has no ${AppFiles.fileName}.';
  try {
    for (final f in AppFiles.parse(list.readAsStringSync())) {
      if (!io.File(AppFiles.under(dir, f)).existsSync()) return '${AppFiles.fileName} lists $f, but the zip has no such file.';
    }
  } on FormatException catch (e) {
    return 'The release is refused: ${e.message} (${e.source}).';
  }
  return null;
}
