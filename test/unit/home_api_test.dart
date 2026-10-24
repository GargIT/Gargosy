import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:dio/dio.dart';

import '../helpers/fake_dio_adapter.dart';

void main() {
  RommLibraryApi api(FakeDioAdapter a) => RommLibraryApi(fakeDio(a), () => Options());

  Map<String, dynamic> rom(int id, String name, DateTime? released) => {
    'id': id,
    'name': name,
    'platform_id': 1,
    'metadatum': {'first_release_date': released?.millisecondsSinceEpoch},
  };

  test("For you: RomM 5.4's recommendations, their games in order; none from an older RomM", () async {
    final a = FakeDioAdapter(
      (_) => (
        status: 200,
        body: [
          {'rom': rom(7, 'Metroid Prime', null), 'score': 0.9, 'reasons': []},
          {'rom': rom(8, 'Super Metroid', null), 'score': 0.8, 'reasons': []},
        ],
      ),
    );
    final games = await api(a).recommended(limit: 12);
    expect([for (final g in games) g.name], ['Metroid Prime', 'Super Metroid']);
    expect((a.requests.single.path, a.requests.single.queryParameters['limit']), ('/api/recommendations', 12));
    expect(await api(FakeDioAdapter((_) => (status: 404, body: {}))).recommended(), isEmpty);
  });

  test(
    'On this day: asks for the day before this year, oldest first; an older RomM that ignores it gives none',
    () async {
      final today = DateTime(2026, 10, 24);
      final a = FakeDioAdapter(
        (_) => (
          status: 200,
          body: {
            'items': [rom(1, 'Super Mario Land 2', DateTime.utc(1992, 10, 24))],
            'total': 3,
          },
        ),
      );
      final page = await api(a).releasedOn(today);
      expect((page.games.single.name, page.total), ('Super Mario Land 2', 3));
      final q = a.requests.single.queryParameters;
      expect(q['released_days'], ['10-24']);
      expect(q['released_before_year'], 2026);
      expect((q['order_by'], q['order_dir']), ('first_release_date', 'asc'));

      final older = FakeDioAdapter(
        (_) => (
          status: 200,
          body: {
            'items': [rom(1, 'Okami', DateTime.utc(2006, 4, 20)), rom(2, 'Ico', null)],
            'total': 1482,
          },
        ),
      );
      final none = await api(older).releasedOn(today);
      expect(none.games, isEmpty);
      expect(none.total, 0);
      expect((await api(older).releasedOn(DateTime(2026, 1, 1))).total, 0, reason: 'no request on 1 January');
    },
  );
}
