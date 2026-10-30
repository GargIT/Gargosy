import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/age_filter.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/profiles/age_limit.dart';

import '../helpers/fake_dio_adapter.dart';
import '../helpers/game_fixtures.dart';

void main() {
  late FakeDioAdapter server;
  late Dio base;

  setUp(() {
    server = FakeDioAdapter((r) {
      if (r.queryParameters['with_filter_values'] == true && r.queryParameters['limit'] == 1) {
        return (
          status: 200,
          body: {
            'items': [],
            'total': 0,
            'filter_values': {
              'age_ratings': ['3', '7', '12', '16', '18', 'E', 'T', 'M', 'RP'],
            },
          },
        );
      }
      return (
        status: 200,
        body: {
          'items': [gameJson(1, 'G')],
          'total': 1,
        },
      );
    });
    base = Dio(BaseOptions(baseUrl: 'https://romm.example'))..httpClientAdapter = server;
  });

  RommLibraryApi api(AgeLimit limit) => RommLibraryApi(ageFilteredDio(base, limit, Options.new), Options.new);

  Map<String, dynamic> lastGallery() => server.requests.last.queryParameters;

  test('no limit: the requests go as they were, nothing more is asked', () async {
    expect(ageFilteredDio(base, AgeLimit.off, Options.new), same(base));
    await api(AgeLimit.off).page(const GalleryQuery());
    expect(server.requests, hasLength(1));
    expect(lastGallery().containsKey('age_ratings'), isFalse);
  });

  test("a limit: RomM's ratings read once, those above it left out with none", () async {
    final a = api(const AgeLimit(maxAge: 12));
    await a.page(const GalleryQuery());
    await a.page(const GalleryQuery(), offset: 48);
    expect(server.requests, hasLength(3), reason: 'the ratings once, then two pages');
    expect(lastGallery()['age_ratings'], ['16', '18', 'T', 'M']);
    expect(lastGallery()['age_ratings_logic'], 'none');
    expect(lastGallery()['offset'], 48);
  });

  test('Hide unrated: only the allowed ratings, with any', () async {
    await api(const AgeLimit(maxAge: 7, hideUnrated: true)).page(const GalleryQuery());
    expect(lastGallery()['age_ratings'], ['3', '7', 'E']);
    expect(lastGallery()['age_ratings_logic'], 'any');
  });

  test("RomM's ratings unreadable: the page still comes, unfiltered, to be checked game by game", () async {
    server = FakeDioAdapter(
      (r) => r.queryParameters['with_filter_values'] == true
          ? (status: 500, body: 'no')
          : (
              status: 200,
              body: {
                'items': [gameJson(1, 'G')],
                'total': 1,
              },
            ),
    );
    base.httpClientAdapter = server;
    final page = await api(const AgeLimit(maxAge: 12)).page(const GalleryQuery());
    expect(page.games, hasLength(1));
    expect(lastGallery().containsKey('age_ratings'), isFalse);
  });

  test('For you and Similar games are checked game by game; Random draws again', () async {
    final mature = {
      ...gameJson(2, 'M'),
      'metadatum': {
        'age_ratings': ['ESRB:M'],
      },
    };
    var draws = 0;
    server = FakeDioAdapter((r) {
      if (r.path.contains('recommendations') || r.path.contains('similar')) {
        return (
          status: 200,
          body: [
            {'rom': gameJson(1, 'G')},
            {'rom': mature},
          ],
        );
      }
      if (r.queryParameters['with_filter_values'] == true && r.queryParameters['limit'] == 1) {
        return (
          status: 200,
          body: {
            'items': [],
            'total': 0,
            'filter_values': {'age_ratings': []},
          },
        );
      }
      draws++;
      return (
        status: 200,
        body: {
          'items': [draws < 3 ? mature : gameJson(1, 'G')],
          'total': 1,
        },
      );
    });
    base.httpClientAdapter = server;
    final a = AgeLimitedLibraryApi(api(const AgeLimit(maxAge: 12)), const AgeLimit(maxAge: 12));
    expect([for (final g in await a.recommended()) g.id], ['1']);
    expect([for (final g in await a.similar('9')) g.id], ['1']);
    expect((await a.randomGame())?.id, '1');
  });
}
