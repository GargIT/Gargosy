import '../core/romm/romm_library_api.dart';
import '../core/romm/romm_models.dart';

/// Whether [g] belongs to [q]'s scope (its platform, collection, favourites,
/// played games), told from the game itself: On this PC needs no RomM.
bool inGalleryScope(
  Game g,
  GalleryQuery q, {
  Set<int> collectionRomIds = const {},
  Set<String> favouriteIds = const {},
}) {
  if (q.platformId != null && g.platformId != q.platformId) return false;
  if (q.inCollection && !collectionRomIds.contains(int.tryParse(g.id))) return false;
  if (q.favourites && !favouriteIds.contains(g.id)) return false;
  if (q.lastPlayedOnly && g.lastPlayed == null) return false;
  return true;
}

/// On this PC: [games] (the profile's downloaded ones) in [q]'s scope, with
/// its filter text, genres and regions, in its order. Gargosy sorts them
/// itself; a game without the value goes last either way, as RomM does.
List<Game> localGallery(
  List<Game> games,
  GalleryQuery q, {
  required bool Function(Game) inScope,
  required DateTime? Function(Game) installedAt,
}) {
  final term = q.search?.trim().toLowerCase() ?? '';
  final list = [
    for (final g in games)
      if (inScope(g) &&
          (term.isEmpty || g.name.toLowerCase().contains(term) || g.displayName.toLowerCase().contains(term)) &&
          (q.genres.isEmpty || g.genres.any(q.genres.contains)) &&
          (q.regions.isEmpty || g.regions.any(q.regions.contains)))
        g,
  ];
  int byName(Game a, Game b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  // Best match is RomM's ranking; on this PC the names' order stands in.
  if (q.sort == GallerySort.name || q.sort == GallerySort.bestMatch) {
    list.sort((a, b) => q.descending ? byName(b, a) : byName(a, b));
    return list;
  }
  final keys = {for (final g in list) g: sortValue(g, q.sort, installedAt)};
  list.sort((a, b) {
    final ka = keys[a], kb = keys[b];
    if (ka == null || kb == null) {
      if (ka != null) return -1;
      if (kb != null) return 1;
      return byName(a, b);
    }
    final c = ka.compareTo(kb);
    if (c != 0) return q.descending ? -c : c;
    return byName(a, b);
  });
  return list;
}

/// [g]'s value for [sort], or null when it has none (RomM's unset: no date,
/// no metadata, a 0 rating or completion).
Comparable<Object>? sortValue(Game g, GallerySort sort, DateTime? Function(Game) installedAt) {
  int? positive(int v) => v > 0 ? v : null;
  return switch (sort) {
    GallerySort.name || GallerySort.bestMatch => g.displayName.toLowerCase(),
    GallerySort.recentlyAdded => g.createdAt,
    GallerySort.lastPlayed => g.lastPlayed,
    GallerySort.releaseDate => g.firstReleaseDate,
    GallerySort.rating => g.averageRating,
    GallerySort.size => positive(g.fileSize),
    GallerySort.players => mostPlayers(g.playerCount),
    GallerySort.length => g.hltbMainStory,
    GallerySort.myRating => positive(g.userRating),
    GallerySort.completion => positive(g.completion),
    GallerySort.status => (g.status?.isEmpty ?? true) ? null : g.status,
    GallerySort.downloaded => installedAt(g),
  };
}

/// The most players a `player_count` such as "1", "1-4" or "2 - 8" allows.
int? mostPlayers(String? count) {
  final numbers = RegExp(r'\d+').allMatches(count ?? '').map((m) => int.parse(m.group(0)!));
  return numbers.isEmpty ? null : numbers.reduce((a, b) => a > b ? a : b);
}

/// The genres and regions [games] have: the filter sheet's choices On this PC.
FilterValues filterValuesOf(Iterable<Game> games) => FilterValues(
  genres: {for (final g in games) ...g.genres}.toList()..sort(),
  regions: {for (final g in games) ...g.regions}.toList()..sort(),
);
