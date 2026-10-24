import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/local_gallery.dart';
import 'package:gargosy/ui/widgets/gallery_bar.dart';

void main() {
  group('withSearch (#132)', () {
    test('Search: a term typed into an empty box sorts by Best match, cleared goes back to Name', () {
      const q = GalleryQuery();
      final typed = q.withSearch(' zelda ', bestMatch: true);
      expect((typed.search, typed.sort), ('zelda', GallerySort.bestMatch));
      expect(typed.toParams(offset: 0, limit: 1)['order_by'], '', reason: "RomM's relevance");
      final more = typed.withSearch('zelda ii', bestMatch: true);
      expect(more.sort, GallerySort.bestMatch);
      final cleared = more.withSearch('', bestMatch: true);
      expect((cleared.search, cleared.sort, cleared.descending), (null, GallerySort.name, false));
    });

    test('a sort picked by hand is kept; elsewhere a term keeps the sort', () {
      const rated = GalleryQuery(sort: GallerySort.rating, descending: true);
      expect(rated.withSearch('mario', bestMatch: true).sort, GallerySort.rating);
      const byName = GalleryQuery(search: 'mario');
      expect(
        byName.withSearch('mario kart', bestMatch: true).sort,
        GallerySort.name,
        reason: 'Name picked while searching',
      );
      expect(const GalleryQuery().withSearch('mario').sort, GallerySort.name);
    });

    test('Best match never stays without a term', () {
      const q = GalleryQuery(search: 'mario', sort: GallerySort.bestMatch);
      expect(q.withSearch(null).sort, GallerySort.name);
      expect(q.withSearch('  ').search, isNull);
    });
  });

  test('Sort by offers Best match only while searching', () {
    expect(sortsFor(thisPc: false), isNot(contains(GallerySort.bestMatch)));
    expect(sortsFor(thisPc: false, searching: true).first, GallerySort.bestMatch);
  });

  test('On this PC orders Best match by name', () {
    Game g(int id, String name) => Game.fromJson({'id': id, 'name': name, 'platform_id': 1});
    final list = localGallery(
      [g(1, 'Zelda II'), g(2, 'A Link to the Past Zelda'), g(3, 'Mario')],
      const GalleryQuery(search: 'zelda', sort: GallerySort.bestMatch),
      inScope: (_) => true,
      installedAt: (_) => null,
    );
    expect([for (final x in list) x.name], ['A Link to the Past Zelda', 'Zelda II']);
  });
}
