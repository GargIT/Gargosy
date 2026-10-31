import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_play_sessions.dart';
import 'package:gargosy/library/download_schedule.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/play/play_engine.dart';
import 'package:gargosy/play/play_limits.dart';
import 'package:gargosy/play/play_time.dart';
import 'package:gargosy/play/quit_combo.dart';
import 'package:gargosy/profiles/age_limit.dart';
import 'package:gargosy/profiles/play_limit.dart';
import 'package:gargosy/profiles/profile.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/screens/settings/age_limit_card.dart';

import '../helpers/fake_dio_adapter.dart';
import '../helpers/game_fixtures.dart';
import 'play_controller_test.dart' show FakeEngine;

class _Remote implements PlaySessionsApi {
  _Remote(this.sessions, {this.fails = false});
  final List<RemoteSession> sessions;
  final bool fails;
  DateTime? askedSince;

  @override
  Future<void> record(List<PlaySessionRecord> sessions) async {}

  @override
  Future<PlayTime?> timeFor(String gameId) async => null;

  @override
  Future<List<RemoteSession>?> sessionsSince(DateTime since) async {
    askedSince = since;
    if (fails) throw StateError('offline');
    return sessions;
  }
}

void main() {
  final now = DateTime(2026, 10, 31, 16);

  group('may a game start, and until when', () {
    test('no limit: yes, with no end', () {
      expect((allowanceFor(PlayLimit.off, const Duration(hours: 9), now) as PlayAllowed).until, isNull);
    });

    test('minutes a day: what is left from now; used up, back tomorrow at midnight', () {
      const limit = PlayLimit(minutesPerDay: 60);
      expect(
        (allowanceFor(limit, const Duration(minutes: 20), now) as PlayAllowed).until,
        now.add(const Duration(minutes: 40)),
      );
      final refused = allowanceFor(limit, const Duration(minutes: 60), now) as PlayRefused;
      expect(refused.backAt, DateTime(2026, 11, 1));
      expect(refused.reason, "Today's play time is used up. Back at 00:00 tomorrow.");
    });

    test('a window: refused outside it until it opens; inside it, until it closes or the minutes run out', () {
      const window = DownloadWindow(15 * 60, 20 * 60);
      final early =
          allowanceFor(const PlayLimit(window: window), Duration.zero, DateTime(2026, 10, 31, 9)) as PlayRefused;
      expect(early.backAt, DateTime(2026, 10, 31, 15));
      expect(early.reason, 'This profile plays 15:00–20:00. Back at 15:00.');
      final late =
          allowanceFor(const PlayLimit(window: window), Duration.zero, DateTime(2026, 10, 31, 21)) as PlayRefused;
      expect(late.backAt, DateTime(2026, 11, 1, 15));
      expect(
        (allowanceFor(const PlayLimit(window: window), Duration.zero, now) as PlayAllowed).until,
        DateTime(2026, 10, 31, 20),
      );
      const both = PlayLimit(minutesPerDay: 30, window: window);
      expect((allowanceFor(both, Duration.zero, now) as PlayAllowed).until, now.add(const Duration(minutes: 30)));
      expect(
        (allowanceFor(both, Duration.zero, DateTime(2026, 10, 31, 19, 50)) as PlayAllowed).until,
        DateTime(2026, 10, 31, 20),
      );
      // Used up with a window: back when tomorrow's window opens.
      expect((allowanceFor(both, const Duration(minutes: 30), now) as PlayRefused).backAt, DateTime(2026, 11, 1, 15));
      // Less than a minute left is used up: a start that would last seconds is never logged.
      expect(allowanceFor(both, const Duration(minutes: 29, seconds: 30), now), isA<PlayRefused>());
    });

    test('a window over midnight: its minutes count from when it opened, not from 00:00', () {
      const limit = PlayLimit(minutesPerDay: 60, window: DownloadWindow(20 * 60, 2 * 60));
      expect(playDayStart(limit, DateTime(2026, 10, 31, 23)), DateTime(2026, 10, 31, 20));
      expect(playDayStart(limit, DateTime(2026, 11, 1, 1)), DateTime(2026, 10, 31, 20));
      expect(playDayStart(const PlayLimit(minutesPerDay: 60), DateTime(2026, 11, 1, 1)), DateTime(2026, 11, 1));
      final used = allowanceFor(limit, const Duration(hours: 1), DateTime(2026, 11, 1, 0, 30)) as PlayRefused;
      expect(used.backAt, DateTime(2026, 11, 1, 20), reason: "back when tonight's window opens");
    });

    test('a session over midnight counts only its part of the day', () {
      final day = DateTime(2026, 10, 31);
      expect(
        playedOn(day, [
          (DateTime(2026, 10, 30, 23, 30), DateTime(2026, 10, 31, 0, 20)),
          (DateTime(2026, 10, 31, 10), DateTime(2026, 10, 31, 10, 15)),
          (DateTime(2026, 10, 31, 23, 50), DateTime(2026, 11, 1, 0, 30)),
        ]),
        const Duration(minutes: 20 + 15 + 10),
      );
    });

    test('kept in profile.json; parents are profiles without either limit', () {
      final base = Profile(
        id: 'kid',
        name: 'Kid',
        colorIndex: 0,
        serverUrl: 'http://romm',
        rommUserId: 2,
        rommUsername: 'kid',
        createdAt: DateTime(2026, 2),
      );
      final kid = base.copyWith(playLimit: const PlayLimit(minutesPerDay: 90, window: DownloadWindow(900, 1200)));
      expect(Profile.fromJson(kid.toJson()).playLimit, kid.playLimit);
      expect(Profile.fromJson(base.toJson()).playLimit, PlayLimit.off);
      final older = Profile.fromJson({...base.toJson(), 'id': 'p', 'createdAt': DateTime(2026).toIso8601String()});
      expect(guardiansOf([older, kid], kid), isEmpty, reason: 'no PIN');
      expect(older.ageLimit, AgeLimit.off);
    });
  });

  group("today's play", () {
    test("this PC's and RomM's other devices', never this PC's twice; offline, this PC's only", () async {
      final log = <PlaySessionRecord>[
        PlaySessionRecord(gameId: '1', start: DateTime(2026, 10, 31, 10), end: DateTime(2026, 10, 31, 10, 30)),
      ];
      final remote = _Remote([
        (deviceId: 'other', start: DateTime(2026, 10, 31, 12), end: DateTime(2026, 10, 31, 12, 20)),
        (deviceId: 'this', start: DateTime(2026, 10, 31, 10), end: DateTime(2026, 10, 31, 10, 30)),
      ]);
      Future<Duration> used(PlaySessionsApi? api, String? device) =>
          playedSince(DateTime(2026, 10, 31), log: _Log(log), api: api, deviceId: device, now: now);
      expect(await used(remote, 'this'), const Duration(minutes: 50));
      expect(remote.askedSince, DateTime(2026, 10, 30), reason: 'from a day before: a session may run past midnight');
      expect(
        await used(remote, null),
        const Duration(minutes: 50),
        reason: 'not known as a device: this PC\'s own matched by its times',
      );
      final moved = _Remote([
        // The folder came from another PC: its sessions are in this log and on RomM under that PC.
        (deviceId: 'pc-a', start: DateTime(2026, 10, 31, 10, 0, 1), end: DateTime(2026, 10, 31, 10, 30, 1)),
      ]);
      expect(await used(moved, 'this'), const Duration(minutes: 30));
      expect(await used(_Remote(const [], fails: true), 'this'), const Duration(minutes: 30));
      expect(await used(null, 'this'), const Duration(minutes: 30), reason: 'offline: this PC only');
    });
  });

  test("RomM's sessions since a time: its times read as UTC; a RomM that won't say gives none", () async {
    var status = 200;
    final server = FakeDioAdapter(
      (r) => (
        status: status,
        body: [
          {'device_id': 'd1', 'start_time': '2026-10-31T10:00:00', 'end_time': '2026-10-31T10:30:00+00:00'},
          {'device_id': null, 'start_time': 'bad', 'end_time': '2026-10-31T11:00:00Z'},
        ],
      ),
    );
    final api = RommPlaySessions(fakeDio(server), Options.new);
    final list = (await api.sessionsSince(DateTime.utc(2026, 10, 30)))!;
    expect(server.requests.single.queryParameters['start_after'], '2026-10-30T00:00:00.000Z');
    expect(list.single.deviceId, 'd1');
    expect(list.single.start, DateTime.utc(2026, 10, 31, 10).toLocal());
    expect(list.single.end.difference(list.single.start), const Duration(minutes: 30));
    status = 403;
    expect(await api.sessionsSince(DateTime(2026)), isNull);
  });

  group('while a game runs (fake clock)', () {
    late FakeEngine engine;
    late int warnings;
    setUp(() {
      engine = FakeEngine()..closable = true;
      warnings = 0;
    });

    ProviderContainer container(FakeAsync async, PlayLimit limit) => ProviderContainer(
      overrides: [
        playEngineProvider.overrideWithValue(engine),
        quitButtonsProvider.overrideWithValue(null),
        playLimitProvider.overrideWithValue(limit),
        playClockProvider.overrideWithValue(() => now.add(async.elapsed)),
        playTimeLogProvider.overrideWithValue(null),
        playSessionsApiProvider.overrideWithValue(null),
        playLimitWarningProvider.overrideWithValue(() => warnings++),
      ],
    );

    test('a warning five minutes before, then the game is closed and the session ends as usual', () {
      fakeAsync((async) {
        final c = container(async, const PlayLimit(minutesPerDay: 30));
        c.read(playControllerProvider.notifier).play(game(1, 'G'));
        async.elapse(Duration.zero);
        expect(c.read(playControllerProvider).runningGameId, '1');
        async.elapse(const Duration(minutes: 24));
        expect(warnings, 0);
        async.elapse(const Duration(minutes: 1, seconds: 1));
        expect(warnings, 1);
        expect(engine.closes, 0);
        async.elapse(const Duration(minutes: 5));
        expect(engine.closes, 1);
        async.elapse(Duration.zero);
        expect(c.read(playControllerProvider).runningGameId, isNull);
        expect(c.read(playControllerProvider).message, startsWith('Play time is up for now.'));
        c.dispose();
      });
    });

    test("a close that didn't work is tried again; a limit shortened during the game counts", () {
      fakeAsync((async) {
        var limit = const PlayLimit(minutesPerDay: 60);
        final c = ProviderContainer(
          overrides: [
            playEngineProvider.overrideWithValue(engine),
            quitButtonsProvider.overrideWithValue(null),
            playLimitProvider.overrideWith((ref) => limit),
            playClockProvider.overrideWithValue(() => now.add(async.elapsed)),
            playTimeLogProvider.overrideWithValue(null),
            playSessionsApiProvider.overrideWithValue(null),
            playLimitWarningProvider.overrideWithValue(() => warnings++),
          ],
        );
        engine.closeFails = 2;
        c.read(playControllerProvider.notifier).play(game(1, 'G'));
        async.elapse(const Duration(minutes: 10));
        expect(engine.closes, 0);
        limit = const PlayLimit(minutesPerDay: 20);
        c.invalidate(playLimitProvider);
        async.elapse(const Duration(minutes: 10, seconds: 5));
        expect(warnings, 1);
        expect(engine.closes, 1, reason: 'at 20 minutes, the new limit');
        async.elapse(const Duration(seconds: 30));
        expect(engine.closes, 3, reason: 'tried again until it closes');
        async.elapse(Duration.zero);
        expect(c.read(playControllerProvider).runningGameId, isNull);
        async.elapse(const Duration(minutes: 5));
        expect(engine.closes, 3);
        c.dispose();
      });
    });

    test('a game ended before the limit: nothing closes later', () {
      fakeAsync((async) {
        final c = container(async, const PlayLimit(minutesPerDay: 30));
        c.read(playControllerProvider.notifier).play(game(1, 'G'));
        async.elapse(const Duration(minutes: 10));
        engine.running!.complete(const PlayResult('Save synced'));
        async.flushMicrotasks();
        async.elapse(const Duration(hours: 1));
        expect(engine.closes, 0);
        expect(warnings, 0);
        c.dispose();
      });
    });

    test('outside its hours Play is refused and says when; an emulator on its own too', () {
      fakeAsync((async) {
        final c = container(async, const PlayLimit(window: DownloadWindow(18 * 60, 20 * 60)));
        String? said;
        c.read(playControllerProvider.notifier).play(game(1, 'G')).then((r) => said = r);
        async.elapse(Duration.zero);
        expect(said, 'This profile plays 18:00–20:00. Back at 18:00.');
        expect(engine.steps, isEmpty);
        expect(c.read(playControllerProvider).runningGameId, isNull);
        c.read(playControllerProvider.notifier).openEmulator('pcsx2', 'PCSX2', 'x.exe').then((r) => said = r);
        async.elapse(Duration.zero);
        expect(said, "An emulator can't be opened on its own with a play time limit.");
        c.dispose();
      });
    });
  });
}

class _Log implements PlayTimeLog {
  _Log(this.all);
  @override
  final List<PlaySessionRecord> all;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
