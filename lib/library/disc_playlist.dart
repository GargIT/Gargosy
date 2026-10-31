import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../profiles/app_root.dart';
import '../profiles/path_guard.dart';

/// #230: a multi-disc game (a folder of discs in `roms\`) without an `.m3u`
/// gets one for the emulators that switch discs through a playlist, written
/// in `userdata\app\temp\launch\`, never in `roms\`. It's named after disc
/// 1, so the emulator names saves and states as it would for disc 1 itself.
class DiscPlaylist {
  /// The emulators that take an `.m3u` as their content.
  static const emulators = {'retroarch', 'duckstation'};

  /// Where this session's playlists go.
  static String dir(AppRoot root) => p.join(root.appData, 'temp', 'launch');

  /// The discs of the game folder [folder], disc 1 first: a `.cue` per disc
  /// when there are any (their `.bin` tracks are the cue's), else the disc
  /// images; none when there are fewer than two, or the folder has its own
  /// `.m3u`.
  static List<String> discsIn(String folder) {
    final dir = io.Directory(folder);
    if (!dir.existsSync()) return const [];
    final files = [
      for (final e in dir.listSync(followLinks: false))
        if (e is io.File) e.path,
    ];
    String ext(String f) => p.extension(f).toLowerCase();
    if (files.any((f) => ext(f) == '.m3u')) return const [];
    final cues = files.where((f) => ext(f) == '.cue').toList();
    final discs = cues.isNotEmpty ? cues : files.where((f) => _images.contains(ext(f))).toList();
    if (discs.length < 2) return const [];
    return discs..sort(_byDisc);
  }

  static const _images = {'.chd', '.iso', '.pbp', '.ccd', '.cso', '.img', '.bin'};

  /// By the disc number in the name ("(Disc 2)", "CD 2"), else by name.
  static int _byDisc(String a, String b) {
    final da = discNumber(p.basename(a)), db = discNumber(p.basename(b));
    if (da != null && db != null && da != db) return da.compareTo(db);
    return p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase());
  }

  /// The disc number in [name]: `(Disc 2)`, `Disc2`, `(CD 2)`; null without.
  static int? discNumber(String name) {
    final m = RegExp(r'\b(?:disc|disk|cd)\s*(\d+)', caseSensitive: false).firstMatch(name);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// The playlist to start [romPath] (a disc in a game folder) with in
  /// [emulatorId], written under [root]'s temp through [guard] (one per
  /// game, [gameId]); null when the emulator takes none, or the folder has
  /// one disc or its own playlist.
  static String? writeFor(
    String romPath, {
    required String emulatorId,
    required String gameId,
    required AppRoot root,
    required PathGuard guard,
  }) {
    if (!emulators.contains(emulatorId) || !io.File(romPath).existsSync()) return null;
    final discs = discsIn(p.dirname(romPath));
    if (discs.isEmpty) return null;
    final folder = guard.check(p.join(dir(root), gameId));
    io.Directory(folder).createSync(recursive: true);
    final playlist = guard.check(p.join(folder, '${p.basenameWithoutExtension(discs.first)}.m3u'));
    io.File(playlist).writeAsStringSync('${discs.map(p.absolute).join('\n')}\n');
    return playlist;
  }
}
