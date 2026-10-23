import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';

import '../helpers/fake_dio_adapter.dart';
import '../helpers/game_fixtures.dart';

Map<String, dynamic> coll(int id, String name, {bool fav = false, int user = 7, List<int> roms = const []}) => {
  'id': id,
  'name': name,
  'description': '',
  'rom_ids': roms,
  'rom_count': roms.length,
  'path_cover_large': null,
  'path_cover_small': null,
  'is_favorite': fav,
  'is_public': false,
  'user_id': user,
  'owner_username': user == 7 ? 'anna' : 'bob',
};

void main() {
  RommLibraryApi api(FakeDioAdapter a) =>
      RommLibraryApi(fakeDio(a), () => Options(headers: {'Authorization': 'Bearer t'}));

  test('a gallery page sends sort, scope and filters, and reads games, total and filter values', () async {
    final a = FakeDioAdapter(
      (r) => (
        status: 200,
        body: {
          'items': [gameJson(1, 'Burnout 3'), gameJson(2, 'Okami')],
          'total': 120,
          'filter_values': {
            'genres': ['Racing', 'Action'],
            'regions': ['USA'],
          },
        },
      ),
    );
    final q = const GalleryQuery(
      platformId: 5,
      sort: GallerySort.recentlyAdded,
      descending: true,
    ).copyWith(genres: {'Racing'});
    final page = await api(a).page(q, offset: 48, withFilterValues: true);
    expect(page.games.map((g) => g.name), ['Burnout 3', 'Okami']);
    expect(page.total, 120);
    expect(page.filters!.genres, ['Action', 'Racing']);
    expect(page.filters!.regions, ['USA']);
    final qp = a.requests.single.queryParameters;
    expect(a.requests.single.path, '/api/roms');
    expect(qp['order_by'], 'created_at');
    expect(qp['order_dir'], 'desc');
    expect(qp['platform_ids'], [5]);
    expect(qp['genres'], ['Racing']);
    expect(qp['offset'], 48);
    expect(qp['limit'], RommLibraryApi.pageSize);
    expect(qp['with_filter_values'], true);
    expect(a.requests.single.headers['Authorization'], 'Bearer t');
  });

  test('favourites, a collection and a search are scoped as RomM expects', () {
    expect(const GalleryQuery(favourites: true).toParams(offset: 0, limit: 1)['favorite'], true);
    expect(const GalleryQuery(collectionId: 3).toParams(offset: 0, limit: 1)['collection_id'], 3);
    expect(const GalleryQuery(search: '  zelda ').toParams(offset: 0, limit: 1)['search_term'], 'zelda');
    expect(const GalleryQuery(search: '   ').toParams(offset: 0, limit: 1).containsKey('search_term'), isFalse);
  });

  test('queries with the same content are equal (they key providers)', () {
    expect(
      const GalleryQuery(platformId: 1).copyWith(genres: {'A', 'B'}),
      const GalleryQuery(platformId: 1).copyWith(genres: {'B', 'A'}),
    );
    expect(const GalleryQuery(platformId: 1), isNot(const GalleryQuery(platformId: 2)));
  });

  test('a reply without total still pages', () async {
    final a = FakeDioAdapter(
      (r) => (
        status: 200,
        body: {
          'items': [gameJson(1, 'A')],
        },
      ),
    );
    expect((await api(a).page(const GalleryQuery(), offset: 10)).total, 11);
  });

  test('collections are read', () async {
    final a = FakeDioAdapter(
      (r) => (
        status: 200,
        body: [
          coll(1, 'Favorites', fav: true, roms: [4]),
          coll(2, 'RPGs', roms: [4, 5]),
        ],
      ),
    );
    final list = await api(a).collections();
    expect(list.map((c) => c.name), ['Favorites', 'RPGs']);
    expect(list.first.isFavorite, isTrue);
    expect(list[1].romIds, {4, 5});
    expect(list[1].romCount, 2);
  });

  test('favouriting adds to the user\'s own favourites collection', () async {
    final a = FakeDioAdapter(
      (r) => r.method == 'GET'
          ? (status: 200, body: [coll(9, 'Favorites', fav: true, user: 8), coll(1, 'Favorites', fav: true)])
          : (status: 200, body: coll(1, 'Favorites', fav: true, roms: [42])),
    );
    final updated = await api(a).setFavourite('42', true, userId: 7);
    expect(updated.romIds, {42});
    final post = a.requests.last;
    expect(post.method, 'POST');
    expect(post.path, '/api/collections/1/roms');
    expect(post.data, {
      'rom_ids': [42],
    });
  });

  test('unfavouriting removes from it', () async {
    final a = FakeDioAdapter(
      (r) => r.method == 'GET'
          ? (
              status: 200,
              body: [
                coll(1, 'Favorites', fav: true, roms: [42]),
              ],
            )
          : (status: 200, body: coll(1, 'Favorites', fav: true)),
    );
    await api(a).setFavourite('42', false, userId: 7);
    expect(a.requests.last.method, 'DELETE');
    expect(a.requests.last.path, '/api/collections/1/roms');
    expect(a.requests.last.data, {
      'rom_ids': [42],
    });
  });

  test('another user\'s favourites are never touched; ours is created once when missing', () async {
    final a = FakeDioAdapter((r) {
      if (r.method == 'GET') return (status: 200, body: [coll(9, 'Favorites', fav: true, user: 8)]);
      if (r.path == '/api/collections') return (status: 200, body: coll(3, 'Favorites', fav: true));
      return (status: 200, body: coll(3, 'Favorites', fav: true, roms: [42]));
    });
    await api(a).setFavourite('42', true, userId: 7);
    final create = a.requests.firstWhere((r) => r.method == 'POST' && r.path == '/api/collections');
    expect(create.queryParameters['is_favorite'], true);
    expect(create.queryParameters['is_public'], false);
    expect(a.requests.last.path, '/api/collections/3/roms');
    expect(a.requests.where((r) => r.path.contains('/9/')), isEmpty);
  });

  test("pages never ask for RomM's whole-library id index", () {
    expect(const GalleryQuery().toParams(offset: 0, limit: 1)['with_rom_id_index'], false);
  });

  test('recently played asks for played games only', () {
    final params = const GalleryQuery(
      lastPlayedOnly: true,
      sort: GallerySort.lastPlayed,
      descending: true,
    ).toParams(offset: 0, limit: 20);
    expect(params['last_played'], true);
    expect(params['order_by'], 'last_played');
  });

  test('a random game is a random page of one, inside the total', () async {
    final a = FakeDioAdapter(
      (r) => (
        status: 200,
        body: {
          'items': [gameJson(1, 'Ico')],
          'total': 50,
        },
      ),
    );
    final g = await api(a).randomGame();
    expect(g!.name, 'Ico');
    expect(a.requests.length, 2);
    final offset = a.requests.last.queryParameters['offset'] as int;
    expect(offset, inInclusiveRange(0, 49));
  });

  test("RomM's letter index is asked only when wanted, and read back", () async {
    final a = FakeDioAdapter(
      (r) => (
        status: 200,
        body: {
          'items': [gameJson(1, 'Ico')],
          'total': 1,
          'char_index': {'i': 0, 'r': 7},
        },
      ),
    );
    final plain = await api(a).page(const GalleryQuery());
    expect(a.requests.last.queryParameters['with_char_index'], false);
    expect(plain.charIndex, isNull);
    final indexed = await api(a).page(const GalleryQuery(), withCharIndex: true);
    expect(a.requests.last.queryParameters['with_char_index'], true);
    expect(indexed.charIndex, {'i': 0, 'r': 7});
  });

  test("a platform's random game is asked within that platform", () async {
    final a = FakeDioAdapter(
      (r) => (
        status: 200,
        body: {
          'items': [gameJson(1, 'Ico')],
          'total': 5,
        },
      ),
    );
    await api(a).randomGame(platformId: 3);
    expect(a.requests.map((r) => r.queryParameters['platform_ids']), everyElement([3]));
  });

  test('smart and virtual collections are read with their kind, covers and query (#121)', () async {
    final a = FakeDioAdapter(
      (r) => (
        status: 200,
        body: r.path.endsWith('/smart')
            ? [
                {
                  ...coll(3, 'Never finished', roms: [1, 2]),
                  'is_smart': true,
                  'filter_summary': 'Status: unfinished',
                  'path_covers_small': ['/a.png', '/b.png'],
                  'updated_at': '2026-10-01T10:00:00Z',
                },
              ]
            : [
                {
                  'id': 'eyJuYW1lIjoiTWFyaW8ifQ',
                  'name': 'Mario',
                  'type': 'franchise',
                  'description': '',
                  'rom_ids': [4, 5, 6],
                  'rom_count': 3,
                  'path_covers_small': <String>[],
                  'path_covers_large': ['/m.png'],
                  'is_virtual': true,
                },
              ],
      ),
    );
    final smart = (await api(a).smartCollections()).single;
    expect(a.requests.last.path, '/api/collections/smart');
    expect(smart.kind, CollectionKind.smart);
    expect(smart.coverPaths, ['/a.png', '/b.png']);
    expect(smart.filterSummary, 'Status: unfinished');
    expect(smart.updatedAt, DateTime.utc(2026, 10, 1, 10));
    expect(smart.query, const GalleryQuery(smartCollectionId: 3));
    expect(smart.query.toParams(offset: 0, limit: 1)['smart_collection_id'], 3);

    final mario = (await api(a).virtualCollections('franchise')).single;
    expect(a.requests.last.path, '/api/collections/virtual');
    expect(a.requests.last.queryParameters['type'], 'franchise');
    expect(mario.kind, CollectionKind.virtual);
    expect(mario.virtualId, 'eyJuYW1lIjoiTWFyaW8ifQ');
    expect(mario.virtualType, 'franchise');
    expect(mario.coverPaths, ['/m.png'], reason: 'the large covers when there are no small ones');
    expect(mario.romCount, 3);
    expect(mario.key, 'virtual-eyJuYW1lIjoiTWFyaW8ifQ');
    expect(mario.query.toParams(offset: 0, limit: 1)['virtual_collection_id'], 'eyJuYW1lIjoiTWFyaW8ifQ');
    expect(mario.query.inCollection, isTrue);
  });

  test("a collection's random game is asked within it", () async {
    final a = FakeDioAdapter(
      (r) => (
        status: 200,
        body: {
          'items': [gameJson(1, 'Ico')],
          'total': 5,
        },
      ),
    );
    await api(a).randomGame(within: const GalleryQuery(smartCollectionId: 3));
    expect(a.requests.map((r) => r.queryParameters['smart_collection_id']), everyElement(3));
  });

  test("the favourites collection's query is the favourites gallery; a scope keeps only the scope", () {
    final fav = RommCollection.fromJson(coll(1, 'Favorites', fav: true));
    expect(fav.query, const GalleryQuery(favourites: true));
    const q = GalleryQuery(collectionId: 2, search: 'zel', sort: GallerySort.rating, genres: {'RPG'});
    expect(q.scopeOnly, const GalleryQuery(collectionId: 2));
  });

  test('notes are read, added private, and deleted; failures throw', () async {
    final a = FakeDioAdapter(
      (r) => switch (r.method) {
        'GET' => (
          status: 200,
          body: [
            {'id': 1, 'title': 'Boss', 'content': 'Brush', 'created_at': '2026-10-01T10:00:00Z'},
          ],
        ),
        'POST' => (status: 201, body: {'id': 2}),
        _ => (status: 204, body: null),
      },
    );
    final notes = await api(a).notes('42');
    expect(notes.single.title, 'Boss');
    await api(a).addNote('42', 'T', 'C');
    expect(a.requests[1].path, '/api/roms/42/notes');
    expect(a.requests[1].data['is_public'], false);
    await api(a).deleteNote('42', 2);
    expect(a.requests[2].method, 'DELETE');
    expect(a.requests[2].path, '/api/roms/42/notes/2');
    final down = FakeDioAdapter((r) => (status: -1, body: null));
    await expectLater(api(down).notes('42'), throwsA(isA<DioException>()));
    await expectLater(api(down).page(const GalleryQuery()), throwsA(isA<DioException>()));
  });

  test('RomNote comes from the reply', () {
    expect(RomNote.fromJson({'id': 1, 'title': 't', 'content': 'c'}).id, 1);
  });
}
