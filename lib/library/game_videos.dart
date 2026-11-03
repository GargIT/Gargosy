import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/romm/romm_models.dart';
import '../core/storage/app_preferences.dart';
import '../profiles/app_root.dart';
import '../profiles/path_guard.dart';

/// Settings → Display → Video previews (#238): app-wide, on by default.
class VideoPreviews {
  static const prefKey = 'ui.videoPreviews';

  static bool on(AppPreferences prefs) => prefs.getBool(prefKey) ?? true;
}

/// Where game videos are kept: beside the image cache, in `userdata\app\`.
String videoCacheDir(AppRoot root) => p.join(root.appData, 'cache', 'videos');

/// A RomM server's folder name there: the same server written with or
/// without a trailing slash or its default port is one folder.
String videoServerKey(String serverUrl) {
  final u = Uri.tryParse(serverUrl.trim().toLowerCase());
  final key = u == null || u.host.isEmpty
      ? serverUrl.trim().toLowerCase()
      : '${u.host}:${u.port}${u.path.replaceAll(RegExp(r'/+$'), '')}';
  return sha1.convert(utf8.encode(key)).toString().substring(0, 12);
}

/// A video file's name: the game's id and its RomM path, so a video RomM
/// replaced is fetched again (the old one goes with the trim).
String videoFileName(Game game) =>
    '${game.id}-${sha1.convert(utf8.encode(game.pathVideo ?? '')).toString().substring(0, 8)}.mp4';

/// Fetches RomM's video into a file, stopping when [cancel] fires.
typedef VideoDownload = Future<void> Function(String pathVideo, String toFile, {CancelToken? cancel});

/// #238: games' videos from RomM (`Game.pathVideo`, MP4), kept on this PC so
/// a page opened again plays at once, under [root] (one folder per server,
/// [dir]); all servers' together up to [maxBytes], past it the ones played
/// longest ago go. One video downloads at a time, only when [mayDownload]
/// says (RomM reachable, the download limits allow it, no ROM downloading);
/// one that failed isn't asked again this session.
class GameVideos {
  GameVideos({
    required this.guard,
    required this.root,
    required this.dir,
    this.download,
    this.mayDownload,
    this.maxBytes = defaultMaxBytes,
  });

  static const defaultMaxBytes = 2 * 1024 * 1024 * 1024;

  /// A partial download older than this was left by a crash.
  static const staleParts = Duration(hours: 1);

  final PathGuard guard;
  final String root;
  final String dir;
  final VideoDownload? download;
  final bool Function()? mayDownload;
  final int maxBytes;

  String? _fetching;
  CancelToken? _cancel;
  Future<String?>? _current;
  final _failed = <String>{};

  /// The trim a download started, running beside it.
  Future<void> _trimming = Future.value();

  /// When the trim the last download started is done (tests).
  Future<void> get trimmed => _trimming;

  String _fileOf(Game game) => guard.check(p.join(dir, videoFileName(game)));

  /// The game's video kept on this PC (now counted as played), or null.
  Future<String?> kept(Game game) async {
    if (!game.hasVideo) return null;
    final f = io.File(_fileOf(game));
    if (!await f.exists()) return null;
    try {
      await f.setLastModified(DateTime.now());
    } on io.FileSystemException {
      // Played anyway; it just counts as older.
    }
    return f.path;
  }

  /// The game's video: the kept one, else RomM's, fetched now. Null when it
  /// has none, it may not be fetched now, another is downloading, or it
  /// failed before.
  Future<String?> fileFor(Game game) async {
    final have = await kept(game);
    if (have != null || !game.hasVideo || _failed.contains(game.id)) return have;
    final fetch = download;
    if (fetch == null || !(mayDownload?.call() ?? true)) return null;
    if (_fetching == game.id) return _current;
    if (_fetching != null) return null;
    _fetching = game.id;
    final cancel = _cancel = CancelToken();
    // The callback returns nothing: returning a future would have this
    // future wait on it.
    return _current = _fetch(game, fetch, cancel).whenComplete(() {
      _fetching = null;
      _cancel = null;
      _current = null;
    });
  }

  /// Stops [game]'s download (its page was left); it's asked again next time.
  void cancel(Game game) {
    if (_fetching == game.id) _cancel?.cancel();
  }

  Future<String?> _fetch(Game game, VideoDownload fetch, CancelToken cancel) async {
    final target = _fileOf(game);
    final part = guard.check('$target.part');
    try {
      await io.Directory(guard.check(dir)).create(recursive: true);
      await fetch(game.pathVideo!, part, cancel: cancel);
      final f = io.File(part);
      if (!await f.exists() || await f.length() == 0) throw StateError('no video');
      await f.rename(target);
    } on Object catch (e) {
      if (!(e is DioException && CancelToken.isCancel(e))) _failed.add(game.id);
      try {
        await io.File(part).delete();
      } on io.FileSystemException {
        // Nothing was written.
      }
      return null;
    }
    // Saved, and played at once; the trim runs beside it, and one that
    // can't finish doesn't undo the video (trimmed next time).
    _trimming = trim(keep: target).catchError((Object _) {});
    return target;
  }

  /// Off the UI isolate: the oldest played videos under [root] removed until
  /// the rest fit [maxBytes], and partial downloads a crash left; [keep] stays.
  Future<void> trim({String? keep}) {
    final at = root, limit = maxBytes, stay = keep;
    final g = guard;
    return Isolate.run(() => _trim(at, limit, stay, g));
  }
}

void _trim(String root, int maxBytes, String? keep, PathGuard guard) {
  final folder = io.Directory(root);
  if (!folder.existsSync()) return;
  final now = DateTime.now();
  final videos = <(io.File, DateTime, int)>[];
  for (final e in folder.listSync(recursive: true)) {
    if (e is! io.File) continue;
    try {
      final stat = e.statSync();
      final name = e.path.toLowerCase();
      if (name.endsWith('.part')) {
        if (now.difference(stat.modified) > GameVideos.staleParts) io.File(guard.check(e.path)).deleteSync();
      } else if (name.endsWith('.mp4')) {
        videos.add((e, stat.modified, stat.size));
      }
    } on io.FileSystemException {
      // Gone or in use: left for next time.
    }
  }
  videos.sort((a, b) => a.$2.compareTo(b.$2));
  var total = videos.fold<int>(0, (n, v) => n + v.$3);
  for (final (file, _, size) in videos) {
    if (total <= maxBytes) break;
    if (keep != null && guard.samePath(file.path, keep)) continue;
    try {
      io.File(guard.check(file.path)).deleteSync();
      total -= size;
    } on io.FileSystemException {
      // Playing now: it stays.
    }
  }
}
