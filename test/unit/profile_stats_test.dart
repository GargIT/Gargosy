import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_service.dart';
import 'package:gargosy/library/profile_stats.dart';

import '../helpers/fake_dio_adapter.dart';
import '../helpers/game_fixtures.dart';

void main() {
  // A Saturday.
  final now = DateTime(2026, 10, 31, 20);
  StatSession s(String game, DateTime start, int minutes) =>
      (gameId: game, start: start, end: start.add(Duration(minutes: minutes)));

  final sessions = [
    s('1', DateTime(2026, 10, 31, 18), 60), // today
    s('1', DateTime(2026, 10, 30, 18), 30), // yesterday
    s('2', DateTime(2026, 10, 29, 18), 90), // Thursday
    s('3', DateTime(2026, 10, 25, 23, 30), 60), // last Sunday, into Monday
    s('2', DateTime(2026, 9, 2, 10), 120), // last month
  ];

  test('week from Monday, month from the 1st, all; a session over a boundary counts from it', () {
    final st = ProfileStats.of(sessions, now);
    expect(st.week, const Duration(minutes: 60 + 30 + 90 + 30));
    expect(st.month, const Duration(minutes: 60 + 30 + 90 + 60));
    expect(st.all, const Duration(minutes: 60 + 30 + 90 + 60 + 120));
    expect(st.sessions, 5);
  });

  test('most played, the longest session, days in a row up to today or yesterday', () {
    final st = ProfileStats.of(sessions, now);
    expect([for (final g in st.mostPlayed) g.gameId], ['2', '1', '3']);
    expect(st.mostPlayed.first.time, const Duration(minutes: 210));
    expect(st.longest!.gameId, '2');
    expect(st.daysInARow, 3, reason: 'Thursday, Friday, Saturday');
    expect(ProfileStats.of(sessions.skip(1).toList(), now).daysInARow, 2, reason: 'none today yet: up to yesterday');
    expect(ProfileStats.of([s('1', DateTime(2026, 10, 28), 10)], now).daysInARow, 0);
    expect(ProfileStats.of(const [], now).all, Duration.zero);
    // A session over midnight plays on both days.
    expect(ProfileStats.of([s('1', DateTime(2026, 10, 30, 23, 30), 120)], now).daysInARow, 2);
    // One that ends before it starts counts nowhere.
    expect(ProfileStats.of([(gameId: '1', start: now, end: now.subtract(const Duration(hours: 1)))], now).sessions, 0);
  });

  test('by platform, an unknown game under Other', () {
    final st = ProfileStats.of(sessions, now);
    final by = st.byPlatform((id) => {'1': 'PlayStation', '2': 'PlayStation'}[id], 'Other');
    expect(by.first.platform, 'PlayStation');
    expect(by.first.time, const Duration(minutes: 300));
    expect(by.last, (platform: 'Other', time: const Duration(minutes: 60)));
  });

  test("RomM's copy of this PC's session counts once", () {
    final local = [s('1', DateTime(2026, 10, 31, 18), 60)];
    final remote = [
      (gameId: '1', start: DateTime(2026, 10, 31, 18, 0, 2), end: DateTime(2026, 10, 31, 19, 0, 1)),
      s('4', DateTime(2026, 10, 31, 12), 15),
    ];
    expect(mergeSessions(local, remote).length, 2);
  });

  test('achievements earned since the 1st, each once, by when it was first unlocked', () {
    final progression = <int, Map<String, dynamic>>{
      10: {
        'earned_achievements': [
          {'id': 'a', 'date': '2026-10-05 10:00:00'},
          {'id': 'b', 'date': '2026-09-30 10:00:00', 'date_hardcore': '2026-10-02T10:00:00Z'},
          {'id': 'c', 'date': '2026-09-01 10:00:00'},
        ],
      },
      11: {
        'earned_achievements': [
          {'id': 'd', 'date': '2026-10-30 22:00:00', 'date_hardcore': '2026-10-30 22:00:00'},
        ],
      },
    };
    // b: softcore in September, hardcore in October: September's.
    expect(achievementsEarnedSince(progression, DateTime(2026, 10)), 2);
  });

  test("RomM away or failing: this PC's play, said; the games named that can be", () async {
    final local = [s('1', DateTime(2026, 10, 31, 18), 60)];
    final offline = await loadStatsView(
      local: local,
      now: now,
      gameOf: (id) async => id == '1' ? game(1, 'Okami') : null,
    );
    expect(offline.thisPcOnly, isTrue);
    expect(offline.finished, isNull);
    expect(offline.games['1']!.name, 'Okami');
    final online = await loadStatsView(
      local: local,
      now: now,
      gameOf: (id) async => throw StateError('offline'),
      remote: () async => [s('2', DateTime(2026, 10, 31, 12), 30)],
      finished: () async => 7,
      progression: () async => throw StateError('no RA'),
    );
    expect(online.thisPcOnly, isFalse);
    expect(online.stats.all, const Duration(minutes: 90));
    expect(online.finished, 7);
    expect(online.achievementsThisMonth, isNull);
    expect(online.games, isEmpty);
  });

  test("games finished: RomM's statuses filter, a game's versions once, its total", () async {
    final server = FakeDioAdapter((r) => (status: 200, body: {'items': [], 'total': 7}));
    final romm = RommService(RomMConfig(baseUrl: 'http://romm', username: '', password: ''))
      ..dio.httpClientAdapter = server;
    expect(await romm.countGamesWithStatuses(const ['finished', 'completed_100']), 7);
    final q = server.requests.single.queryParameters;
    expect(q['statuses'], ['finished', 'completed_100']);
    expect(q['group_by_meta_id'], true);
    expect(q['with_total'], true);
  });
}
