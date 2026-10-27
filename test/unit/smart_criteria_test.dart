import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/library/smart_criteria.dart';

void main() {
  test("a gallery's scope, search, filters and sort, under RomM's names; nothing about paging", () {
    final s = smartCriteriaOf(
      const GalleryQuery(
        platformId: 4,
        search: ' mario ',
        genres: {'Racing', 'Action'},
        regions: {'USA'},
        sort: GallerySort.releaseDate,
        descending: true,
      ),
    );
    expect(s.criteria, {
      'order_by': 'first_release_date',
      'order_dir': 'desc',
      'platform_ids': [4],
      'search_term': 'mario',
      'genres': ['Action', 'Racing'],
      'regions': ['USA'],
    });
    expect(s.leftOut, isEmpty);
    expect(s.picksSomething, isTrue);
  });

  test("a collection's gallery keeps its collection; favourites stay favourites", () {
    expect(smartCriteriaOf(const GalleryQuery(collectionId: 3)).criteria['collection_id'], 3);
    expect(smartCriteriaOf(const GalleryQuery(virtualCollectionId: 'v1')).criteria['virtual_collection_id'], 'v1');
    expect(smartCriteriaOf(const GalleryQuery(favourites: true)).criteria['favorite'], true);
  });

  test("On this PC and the Downloaded order are Gargosy's: said, and sorted by name instead", () {
    final s = smartCriteriaOf(
      const GalleryQuery(platformId: 1, sort: GallerySort.downloaded, descending: true),
      thisPc: true,
    );
    expect(s.leftOut, ['On this PC', 'the Downloaded order']);
    expect(s.criteria['order_by'], 'name');
    expect(s.criteria['order_dir'], 'asc');
  });

  test('Best match needs a term, so it saves as by name', () {
    final s = smartCriteriaOf(const GalleryQuery(search: 'zelda', sort: GallerySort.bestMatch));
    expect(s.criteria['order_by'], 'name');
    expect(s.leftOut, isEmpty);
  });

  test('the whole library picks nothing; a smart collection is not saved again', () {
    expect(smartCriteriaOf(const GalleryQuery()).picksSomething, isFalse);
    expect(canSaveAsSmart(const GalleryQuery(smartCollectionId: 2)), isFalse);
    expect(canSaveAsSmart(const GalleryQuery(platformId: 2)), isTrue);
  });
}
