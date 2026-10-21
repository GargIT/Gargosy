import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/local_gallery.dart';

Game _g(
  int id,
  String name, {
  int platformId = 1,
  int size = 0,
  String? players,
  int? hltb,
  int rating = 0,
  String? status,
  String? created,
  List<String> genres = const [],
  List<String> regions = const [],
}) => Game.fromJson({
  'id': id,
  'name': name,
  'platform_id': platformId,
  'fs_size_bytes': size,
  'created_at': created,
  'hltb_metadata': {'main_story': hltb},
  'regions': regions,
  'metadatum': {'player_count': players, 'genres': genres},
  'rom_user': {'rating': rating, 'status': status},
});

void main() {
  DateTime? never(Game _) => null;
  List<String> names(List<Game> l) => [for (final g in l) g.name];

  group('Game reads what the sorts need', () {
    test("RomM's fs_size_bytes, created_at and HLTB's main story, through the snapshot too", () {
      final g = _g(1, 'A', size: 4096, hltb: 36000, created: '2026-10-01T10:00:00Z');
      expect(g.fileSize, 4096);
      expect(g.hltbMainStory, 36000);
      expect(g.createdAt, DateTime.utc(2026, 10, 1, 10));
      final back = Game.fromJson(g.toJson());
      expect([back.fileSize, back.hltbMainStory, back.createdAt], [4096, 36000, g.createdAt]);
    });
  });

  group('inGalleryScope', () {
    final g = _g(7, 'A', platformId: 2);
    test('platform, collection and favourites are told from the game', () {
      expect(inGalleryScope(g, const GalleryQuery(platformId: 2)), isTrue);
      expect(inGalleryScope(g, const GalleryQuery(platformId: 3)), isFalse);
      expect(inGalleryScope(g, const GalleryQuery(collectionId: 5), collectionRomIds: {7}), isTrue);
      expect(inGalleryScope(g, const GalleryQuery(collectionId: 5), collectionRomIds: {8}), isFalse);
      expect(inGalleryScope(g, const GalleryQuery(favourites: true), favouriteIds: {'7'}), isTrue);
      expect(inGalleryScope(g, const GalleryQuery(favourites: true)), isFalse);
    });
  });

  group('localGallery', () {
    final games = [
      _g(1, 'Gran Turismo 4', size: 300, players: '1-6', hltb: 900, genres: ['Racing'], regions: ['USA']),
      _g(2, '.hack Infection', size: 100, players: '1', rating: 8, status: 'finished', genres: ['RPG']),
      _g(3, 'Burnout 3', size: 200, rating: 6, genres: ['Racing'], regions: ['Europe']),
    ];

    List<String> sorted(GallerySort s, {bool desc = false, DateTime? Function(Game)? at}) => names(
      localGallery(
        games,
        GalleryQuery(sort: s, descending: desc),
        inScope: (_) => true,
        installedAt: at ?? never,
      ),
    );

    test('the filter text, genres and regions narrow it', () {
      List<String> q(GalleryQuery q) => names(localGallery(games, q, inScope: (_) => true, installedAt: never));
      expect(q(const GalleryQuery(search: 'HACK')), ['.hack Infection']);
      expect(q(const GalleryQuery(genres: {'Racing'})), ['Burnout 3', 'Gran Turismo 4']);
      expect(q(const GalleryQuery(genres: {'Racing'}, regions: {'Europe'})), ['Burnout 3']);
    });

    test('by name either way', () {
      expect(sorted(GallerySort.name), ['.hack Infection', 'Burnout 3', 'Gran Turismo 4']);
      expect(sorted(GallerySort.name, desc: true), ['Gran Turismo 4', 'Burnout 3', '.hack Infection']);
    });

    test('by size, players, length; a game without the value goes last either way', () {
      expect(sorted(GallerySort.size, desc: true), ['Gran Turismo 4', 'Burnout 3', '.hack Infection']);
      expect(sorted(GallerySort.players, desc: true), ['Gran Turismo 4', '.hack Infection', 'Burnout 3']);
      expect(sorted(GallerySort.players), ['.hack Infection', 'Gran Turismo 4', 'Burnout 3']);
      expect(sorted(GallerySort.length), ['Gran Turismo 4', '.hack Infection', 'Burnout 3']);
    });

    test('by my rating and status; 0 is unset', () {
      expect(sorted(GallerySort.myRating, desc: true), ['.hack Infection', 'Burnout 3', 'Gran Turismo 4']);
      expect(sorted(GallerySort.status), ['.hack Infection', 'Burnout 3', 'Gran Turismo 4']);
    });

    test('Downloaded: newest download first', () {
      final at = {'1': DateTime(2026, 10, 1), '2': DateTime(2026, 10, 3), '3': DateTime(2026, 10, 2)};
      expect(sorted(GallerySort.downloaded, desc: true, at: (g) => at[g.id]), [
        '.hack Infection',
        'Burnout 3',
        'Gran Turismo 4',
      ]);
    });
  });

  test('mostPlayers reads the highest number', () {
    expect(
      [mostPlayers('1'), mostPlayers('1-4'), mostPlayers('2 - 8'), mostPlayers(null), mostPlayers('')],
      [1, 4, 8, null, null],
    );
  });

  test('filterValuesOf lists the genres and regions present', () {
    final v = filterValuesOf([
      _g(1, 'A', genres: ['RPG', 'Action'], regions: ['USA']),
      _g(2, 'B', genres: ['Action']),
    ]);
    expect(v.genres, ['Action', 'RPG']);
    expect(v.regions, ['USA']);
  });
}
