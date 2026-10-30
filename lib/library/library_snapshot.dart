import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/romm/romm_models.dart';
import '../profiles/json_file.dart';
import '../profiles/path_guard.dart';
import '../profiles/profile_providers.dart';
import '../profiles/profile_paths.dart';
import '../providers/download_providers.dart';

/// The profile's own games on this PC, as RomM described them when they
/// were downloaded or last opened (`profiles\<id>\cache\library.json`). With
/// RomM unreachable they still show, open and play (spec §8).
class LibrarySnapshot {
  LibrarySnapshot(this.file, this.guard);

  final String file;
  final PathGuard guard;

  Map<String, dynamic> _all() {
    try {
      return readJsonObjectSync(file) ?? {};
    } on Object {
      return {}; // damaged: replaced on the next write
    }
  }

  /// The games, by name.
  List<Game> read() {
    final games = <Game>[];
    for (final v in _all().values) {
      try {
        games.add(Game.fromJson(Map<String, dynamic>.from(v as Map)));
      } on Object {
        // one unreadable game doesn't hide the rest
      }
    }
    games.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return games;
  }

  Game? find(String id) {
    final v = _all()[id];
    if (v is! Map) return null;
    try {
      return Game.fromJson(Map<String, dynamic>.from(v));
    } on Object {
      return null;
    }
  }

  Future<void> remember(Game game) => writeJsonObject(guard, file, {..._all(), game.id: game.toJson()});

  /// [games] added (or brought up to date) in one write.
  Future<void> rememberAll(Iterable<Game> games) async {
    final all = _all();
    for (final g in games) {
      all[g.id] = g.toJson();
    }
    await writeJsonObject(guard, file, all);
  }

  Future<void> forget(String id) async {
    final all = _all();
    if (all.remove(id) != null) await writeJsonObject(guard, file, all);
  }
}

final librarySnapshotProvider = Provider<LibrarySnapshot?>((ref) {
  final id = ref.watch(activeProfileProvider.select((c) => c?.profile.id));
  if (id == null) return null;
  final paths = ProfilePaths(ref.watch(appRootProvider), id);
  return LibrarySnapshot(p.join(paths.cache, 'library.json'), paths.guard);
});

/// The profile's games that are downloaded on this PC (from the snapshot),
/// newest download first; Home's Installed games shelf. Without those above
/// the profile's age limit (#224), which RomM's own lists leave out too.
final gamesOnThisPcProvider = Provider<List<Game>>((ref) {
  ref.watch(romFilesVersionProvider);
  final snap = ref.watch(librarySnapshotProvider);
  if (snap == null) return const [];
  final files = ref.watch(romFilesProvider);
  final limit = ref.watch(ageLimitProvider);
  return installedNewestFirst(snap.read(), files.installedAt).where(limit.allows).toList();
});

/// [games] that are on this PC ([installedAt] not null), newest first; the
/// same time keeps their order (by name).
List<Game> installedNewestFirst(List<Game> games, DateTime? Function(Game) installedAt) {
  final at = <Game, DateTime>{for (final g in games) g: ?installedAt(g)};
  final list = [
    for (final g in games)
      if (at.containsKey(g)) g,
  ];
  final index = {for (var i = 0; i < list.length; i++) list[i]: i};
  list.sort((a, b) {
    final byTime = at[b]!.compareTo(at[a]!);
    return byTime != 0 ? byTime : index[a]!.compareTo(index[b]!);
  });
  return list;
}
