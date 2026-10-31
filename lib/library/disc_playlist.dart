import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../profiles/app_root.dart';
import '../profiles/path_guard.dart';

/// #230: a multi-disc game (a folder of numbered discs in `roms\`) without
/// an `.m3u` gets one, for the emulators whose strategy takes it
/// (`EmulatorStrategy.takesDiscPlaylist`), written in
/// `userdata\app\temp\launch\`, never in `roms\`. It lists the discs in
/// order (the emulator boots disc 1) and is named after the disc the game
/// is started from, so the emulator names saves and states as it always
/// did for that game.
class DiscPlaylist {
  /// Where the playlists go, one folder per game.
  static String dir(AppRoot root) => p.join(root.appData, 'temp', 'launch');

  /// The discs of the game folder [folder] in disc order: a `.cue` per disc
  /// when there are cues (their `.bin` tracks are the cue's), else a `.ccd`
  /// per disc (with its `.img`), else the images. None unless there are two
  /// or more, each with a disc number and the same name otherwise (so a
  /// platform's folder of single games never counts), or when the folder
  /// has its own `.m3u` or can't be read.
  static List<String> discsIn(String folder) {
    final List<String> files;
    try {
      files = [
        for (final e in io.Directory(folder).listSync(followLinks: false))
          if (e is io.File) e.path,
      ];
    } on io.FileSystemException {
      return const [];
    }
    String ext(String f) => p.extension(f).toLowerCase();
    if (files.any((f) => ext(f) == '.m3u')) return const [];
    List<String> withExt(Set<String> exts) => files.where((f) => exts.contains(ext(f))).toList();
    final cues = withExt(const {'.cue'});
    final ccds = withExt(const {'.ccd'});
    final discs = cues.isNotEmpty
        ? cues
        : ccds.isNotEmpty
        ? ccds
        : withExt(const {'.chd', '.iso', '.pbp', '.cso', '.img', '.bin'});
    if (discs.length < 2) return const [];
    final names = [for (final d in discs) p.basenameWithoutExtension(d)];
    if (names.any((n) => discNumber(n) == null)) return const [];
    // One game: the same name once the disc tag is taken out.
    if (names.map(_withoutDisc).toSet().length != 1) return const [];
    return discs..sort((a, b) => discNumber(p.basename(a))!.compareTo(discNumber(p.basename(b))!));
  }

  static final _disc = RegExp(r'\b(?:disc|disk)\s*(\d{1,2})\b|\bcd\s+(\d{1,2})\b', caseSensitive: false);

  /// The disc number in [name]: `(Disc 2)`, `Disc2`, `(CD 2)`; null without
  /// (`CD32` is no disc number).
  static int? discNumber(String name) {
    final m = _disc.firstMatch(name);
    return m == null ? null : int.parse(m.group(1) ?? m.group(2)!);
  }

  static String _withoutDisc(String name) =>
      name.replaceAll(_disc, '').replaceAll(RegExp(r'[\s()\[\]_.-]+'), ' ').trim().toLowerCase();

  /// The playlist to start [romPath] (one of a game folder's discs) on,
  /// written under [root]'s temp through [guard], one folder per game
  /// ([gameId]); null when the folder isn't one game's numbered discs, or
  /// anything fails (the game then starts on [romPath] as before).
  static String? writeFor(String romPath, {required String gameId, required AppRoot root, required PathGuard guard}) {
    try {
      final discs = discsIn(p.dirname(romPath));
      if (discs.isEmpty || !discs.any((d) => p.equals(d, romPath))) return null;
      final folder = guard.check(p.join(dir(root), gameId));
      io.Directory(folder).createSync(recursive: true);
      final playlist = guard.check(p.join(folder, '${p.basenameWithoutExtension(romPath)}.m3u'));
      io.File(playlist).writeAsStringSync('${discs.map(p.absolute).join('\n')}\n');
      return playlist;
    } on Object catch (e) {
      debugPrint('[Launch] no disc playlist for $romPath: $e');
      return null;
    }
  }

  /// [playlist]'s folder removed after the session; left when it can't be.
  static void remove(String playlist) {
    try {
      io.Directory(p.dirname(playlist)).deleteSync(recursive: true);
    } on io.FileSystemException {
      // Left in temp; Empty Temp clears it.
    }
  }
}
