import '../core/romm/romm_library_api.dart';
import '../core/romm/romm_models.dart';

/// #226: every game of a gallery's [query] (a collection, a platform) that
/// [skip] doesn't leave out (on this PC, queued already), versions folded as
/// the gallery shows them, in its order. Read from RomM in pages of
/// [pageSize].
Future<List<Game>> gamesToDownload(
  LibraryApi api,
  GalleryQuery query, {
  required bool Function(Game) skip,
  int pageSize = 200,
}) async {
  final out = <Game>[];
  var offset = 0;
  while (true) {
    final page = await api.page(query, offset: offset, limit: pageSize, foldVersions: true);
    for (final g in page.games) {
      if (!skip(g)) out.add(g);
    }
    offset += page.games.length;
    if (page.games.isEmpty || offset >= page.total) return out;
  }
}

/// What [games] add up to on disk, by RomM's sizes.
int sizeOf(Iterable<Game> games) => games.fold(0, (sum, g) => sum + g.fileSize);
