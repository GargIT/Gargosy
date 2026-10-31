import '../core/romm/romm_library_api.dart';
import '../core/romm/romm_models.dart';
import 'game_versions.dart';

/// #226: every game of a gallery's [query] (a collection, a platform) in
/// RomM's order for it, versions folded as the gallery folds them (RomM's
/// `group_by_meta_id`, then `sibling_roms`), without those [skip] leaves out
/// (its file on this PC, queued already) or with a version among [have]
/// (another version of it on this PC or queued). Read from RomM in pages of [pageSize], at most as many as
/// RomM's total asks for.
Future<List<Game>> gamesToDownload(
  LibraryApi api,
  GalleryQuery query, {
  required bool Function(Game) skip,
  Set<String> have = const {},
  int pageSize = 200,
}) async {
  final all = <Game>[];
  var offset = 0;
  int? pages;
  for (var i = 0; pages == null || i < pages; i++) {
    final page = await api.page(query, offset: offset, limit: pageSize, foldVersions: true);
    pages ??= page.total ~/ pageSize + 2;
    all.addAll(page.games);
    offset += page.games.length;
    if (page.games.isEmpty || offset >= page.total) break;
  }
  return [
    for (final g in foldVersions(all))
      if (!skip(g) && !g.siblings.any((v) => have.contains(v.id))) g,
  ];
}

/// What [games] add up to on disk, by RomM's sizes.
int sizeOf(Iterable<Game> games) => games.fold(0, (sum, g) => sum + g.fileSize);
