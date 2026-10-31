import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/romm/romm_service.dart';
import '../emulators/emulator_layout.dart';
import '../profiles/profile_preferences.dart';
import '../providers/engine_providers.dart';
import '../providers/romm_providers.dart';

/// What counts as a screenshot: the images RomM takes.
const screenshotExtensions = {'.png', '.jpg', '.jpeg', '.bmp', '.webp'};

/// The screenshots made in the emulator [layout] describes while a game ran
/// from [start] to [end] (#233): images in its screenshot folders under the
/// profile's [dataDir], with their subfolders, written in that time (a few
/// seconds either side, for the file system's clock), oldest first. Links
/// aren't followed.
List<String> screenshotsTaken(String dataDir, EmulatorLayout layout, DateTime start, DateTime end) {
  final from = start.subtract(const Duration(seconds: 2));
  final to = end.add(const Duration(seconds: 5));
  final found = <(DateTime, String)>[];
  for (final folder in layout.screenshots) {
    final dir = io.Directory(p.join(dataDir, folder));
    if (!dir.existsSync()) continue;
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is! io.File || !screenshotExtensions.contains(p.extension(e.path).toLowerCase())) continue;
        final at = e.statSync().modified;
        if (!at.isBefore(from) && !at.isAfter(to)) found.add((at, e.path));
      }
    } on io.FileSystemException catch (e) {
      debugPrint('[Screenshots] $folder not read: $e');
    }
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

/// One screenshot waiting to reach RomM: the file stays where the emulator
/// wrote it, in the profile's folder.
typedef WaitingScreenshot = ({String gameId, String path});

/// The profile's screenshots on their way to RomM (#233), in its
/// `prefs.json`: added after each game, sent oldest first, kept until RomM
/// has them and tried again after the next game or when the profile opens.
/// Turned off by Settings → Emulator settings → Upload screenshots.
class ScreenshotUploads {
  ScreenshotUploads(this._prefs, {this.upload});

  final ProfilePreferences _prefs;

  /// RomM's upload; null without RomM.
  final Future<void> Function(String gameId, String path)? upload;

  static const key = 'screenshots.waiting';
  static const enabledKey = 'screenshots.upload';

  /// The newest kept: a long time without RomM never grows it past this.
  static const keep = 200;

  bool get enabled => _prefs.getBool(enabledKey) ?? true;
  Future<void> setEnabled(bool on) => _prefs.setBool(enabledKey, on);

  List<WaitingScreenshot> get waiting {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      return [
        if (list is List)
          for (final e in list)
            if (e is Map && e['game'] is String && e['path'] is String)
              (gameId: e['game'] as String, path: e['path'] as String),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _save(List<WaitingScreenshot> list) {
    final kept = list.length > keep ? list.sublist(list.length - keep) : list;
    return _prefs.setString(
      key,
      jsonEncode([
        for (final s in kept) {'game': s.gameId, 'path': s.path},
      ]),
    );
  }

  /// [paths], taken in [gameId], wait to be sent; nothing while turned off.
  Future<void> add(String gameId, List<String> paths) async {
    if (!enabled || paths.isEmpty) return;
    final have = {for (final s in waiting) s.path};
    await _save([
      ...waiting,
      for (final path in paths)
        if (!have.contains(path)) (gameId: gameId, path: path),
    ]);
  }

  /// Sends what's waiting, oldest first, and says how many went. A file gone
  /// or one RomM refuses ([ScreenshotRefused]) is dropped; any other failure
  /// stops, keeping the rest for next time. Never throws.
  Future<int> sendWaiting() => _sending ??= _send().whenComplete(() {
    _sending = null;
  });

  /// One send at a time for every [ScreenshotUploads] (after a game and when
  /// the profile opens may meet): a screenshot is never sent twice.
  static Future<int>? _sending;

  Future<int> _send() async {
    final send = upload;
    if (send == null || !enabled) return 0;
    var sent = 0;
    while (true) {
      final list = waiting;
      if (list.isEmpty) return sent;
      final next = list.first;
      try {
        if (io.File(next.path).existsSync()) {
          await send(next.gameId, next.path);
          sent++;
        }
      } on ScreenshotRefused catch (e) {
        debugPrint('[Screenshots] ${p.basename(next.path)} dropped: $e');
      } on Object catch (e) {
        debugPrint('[Screenshots] not sent, tried again later: $e');
        return sent;
      }
      await _save(waiting.where((s) => s != next).toList());
    }
  }
}

/// The active profile's screenshot uploads; RomM's upload only with RomM.
final screenshotUploadsProvider = Provider<ScreenshotUploads?>((ref) {
  final prefs = ref.watch(profilePrefsProvider);
  if (prefs == null) return null;
  final romm = ref.watch(rommServiceProvider);
  return ScreenshotUploads(prefs, upload: romm?.uploadScreenshot);
});
