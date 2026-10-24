import 'dart:async';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/download_service.dart';
import 'package:gargosy/library/rom_files.dart';
import 'package:gargosy/profiles/path_guard.dart';

/// Writes a small file instead of downloading.
class FakeDownloadService extends DownloadService {
  FakeDownloadService(RomFiles files, PathGuard guard)
    : super(dio: Dio(), auth: Options.new, files: files, guard: guard, tempDir: files.root.appData, urlFor: (g) => '');

  final started = <String>[];

  /// When set, the download reports [holdIn] and waits for this before finishing.
  Completer<void>? hold;
  DownloadPhase holdIn = DownloadPhase.downloading;

  /// One game's own [hold]; [fail] makes a game's download fail.
  final holds = <String, Completer<void>>{};
  final fail = <String>{};

  @override
  Future<void> download(Game game, {void Function(DownloadProgress)? onProgress, CancelToken? cancel}) async {
    started.add(game.id);
    onProgress?.call(const DownloadProgress(DownloadPhase.downloading, received: 5, total: 10));
    final held = holds[game.id] ?? hold;
    if (held != null) {
      onProgress?.call(DownloadProgress(holdIn, received: 5, total: 10));
      cancel?.whenCancel.then((_) {
        if (!held.isCompleted) {
          held.completeError(DioException.requestCancelled(requestOptions: RequestOptions(), reason: 'cancelled'));
        }
      });
      await held.future;
    }
    if (fail.contains(game.id)) throw StateError('no room');
    io.File(files.pathFor(game))
      ..createSync(recursive: true)
      ..writeAsStringSync('rom');
    onProgress?.call(const DownloadProgress(DownloadPhase.done));
  }
}
