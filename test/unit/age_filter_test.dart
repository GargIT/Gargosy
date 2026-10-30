import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/age_filter.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/profiles/age_limit.dart';

import '../helpers/fake_dio_adapter.dart';
import '../helpers/game_fixtures.dart';

void main() {
  late FakeDioAdapter server;
  late int reads;
  late DateTime now;
  const ratings = ['3', '7', '12', '16', '18', 'E', 'T', 'M', 'RP'];

  setUp(() {
    reads = 0;
    now = DateTime(2026, 10, 31, 12);
    server = FakeDioAdapter(
      (r) => (
        status: 200,
        body: {
          'items': [gameJson(1, 'G')],
          'total': 1,
        },
      ),
    );
  });

  /// RomM's library API through the filter for [limit]; [read] gives RomM's
  /// ratings.
  RommLibraryApi api(AgeLimit limit, {Future<List<String>> Function()? read}) {
    final dio = fakeDio(server)
      ..interceptors.add(
        AgeFilterInterceptor(
          limit,
          read ??
              () async {
                reads++;
                return ratings;
              },
          now: () => now,
        ),
      );
    return RommLibraryApi(dio, Options.new);
  }

  Map<String, dynamic> lastAsked() => server.requests.last.queryParameters;

  test('no limit: the requests go as they were, nothing is read', () async {
    await api(AgeLimit.off).page(const GalleryQuery());
    expect(reads, 0);
    expect(lastAsked().containsKey('age_ratings'), isFalse);
  });

  test("a limit: RomM's ratings read once, those above it left out with none", () async {
    final a = api(const AgeLimit(maxAge: 12));
    await a.page(const GalleryQuery());
    await a.page(const GalleryQuery(), offset: 48);
    expect(reads, 1);
    expect(lastAsked()['age_ratings'], ['16', '18', 'T', 'M']);
    expect(lastAsked()['age_ratings_logic'], 'none');
    expect(lastAsked()['offset'], 48);
  });

  test('the ratings are read again after a while: a game scanned since may bring one', () async {
    final a = api(const AgeLimit(maxAge: 12));
    await a.page(const GalleryQuery());
    now = now.add(AgeFilterInterceptor.refresh + const Duration(seconds: 1));
    await a.page(const GalleryQuery());
    expect(reads, 2);
  });

  test('Hide unrated still sends none with the ratings above: a game with one above is out on RomM', () async {
    await api(const AgeLimit(maxAge: 7, hideUnrated: true)).page(const GalleryQuery());
    expect(lastAsked()['age_ratings'], ['12', '16', '18', 'T', 'M']);
    expect(lastAsked()['age_ratings_logic'], 'none');
  });

  test("RomM's ratings unreadable: the list fails, never unfiltered", () async {
    final a = api(const AgeLimit(maxAge: 12), read: () async => throw DioException(requestOptions: RequestOptions()));
    await expectLater(a.page(const GalleryQuery()), throwsA(isA<DioException>()));
    expect(server.requests, isEmpty);
  });

  test('For you, Similar games and On this day are checked game by game; Random draws again', () async {
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
      draws++;
      return (
        status: 200,
        body: {
          'items': [draws < 3 ? mature : gameJson(1, 'G')],
          'total': 1,
        },
      );
    });
    const limit = AgeLimit(maxAge: 12);
    final a = AgeLimitedLibraryApi(api(limit), limit);
    expect([for (final g in await a.recommended()) g.id], ['1']);
    expect([for (final g in await a.similar('9')) g.id], ['1']);
    expect((await a.randomGame())?.id, '1');
  });
}
