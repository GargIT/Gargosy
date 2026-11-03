import 'dart:io' as io;

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

/// #238: games' videos from RomM (`Game.pathVideo`, MP4), kept on this PC so
/// a page opened again plays at once. Up to [maxBytes] in all; past it the
/// ones played longest ago go. One download per game at a time; one that
/// failed isn't asked again this session.
class GameVideos {
  GameVideos({required this.guard, required this.dir, this.download, this.maxBytes = defaultMaxBytes});

  static const defaultMaxBytes = 2 * 1024 * 1024 * 1024;

  final PathGuard guard;
  final String dir;

  /// RomM's video into a file; null while RomM can't be reached.
  final Future<void> Function(String pathVideo, String toFile)? download;
  final int maxBytes;

  final _fetching = <String, Future<String?>>{};
  final _failed = <String>{};

  String _fileOf(Game game) => guard.check(p.join(dir, '${game.id}.mp4'));

  /// The game's video kept on this PC, or null.
  String? kept(Game game) {
    if (!game.hasVideo) return null;
    final f = io.File(_fileOf(game));
    if (!f.existsSync()) return null;
    try {
      f.setLastModifiedSync(DateTime.now());
    } on io.FileSystemException {
      // Played anyway; it just counts as older.
    }
    return f.path;
  }

  /// The game's video: the kept one, else RomM's, fetched now. Null when it
  /// has none, RomM can't send it, or it failed before.
  Future<String?> fileFor(Game game) async {
    final have = kept(game);
    if (have != null || !game.hasVideo || _failed.contains(game.id)) return have;
    final fetch = download;
    if (fetch == null) return null;
    // The callback returns nothing: returning the removed future (this one)
    // would have it wait on itself.
    return _fetching[game.id] ??= _fetch(game, fetch).whenComplete(() {
      _fetching.remove(game.id);
    });
  }

  Future<String?> _fetch(Game game, Future<void> Function(String, String) fetch) async {
    final target = _fileOf(game);
    final part = guard.check('$target.part');
    try {
      io.Directory(guard.check(dir)).createSync(recursive: true);
      await fetch(game.pathVideo!, part);
      final f = io.File(part);
      if (!f.existsSync() || f.lengthSync() == 0) throw StateError('no video');
      f.renameSync(target);
      trim(keep: target);
      return target;
    } on Object {
      _failed.add(game.id);
      try {
        io.File(part).deleteSync();
      } on io.FileSystemException {
        // Nothing was written.
      }
      return null;
    }
  }

  /// The oldest played videos removed until the rest fit [maxBytes]; [keep] stays.
  void trim({String? keep}) {
    final folder = io.Directory(dir);
    if (!folder.existsSync()) return;
    final files = [
      for (final e in folder.listSync())
        if (e is io.File && e.path.toLowerCase().endsWith('.mp4')) e,
    ]..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    var total = files.fold<int>(0, (n, f) => n + f.lengthSync());
    for (final f in files) {
      if (total <= maxBytes) break;
      if (keep != null && guard.samePath(f.path, keep)) continue;
      final size = f.lengthSync();
      try {
        io.File(guard.check(f.path)).deleteSync();
        total -= size;
      } on io.FileSystemException {
        // In use (playing now): it stays.
      }
    }
  }
}
