import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_play_sessions.dart';
import 'package:gargosy/play/play_time.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_preferences.dart';
import 'package:gargosy/ui/widgets/format.dart';

import '../helpers/fake_dio_adapter.dart';
import '../helpers/profile_test_env.dart';

class _FakeApi implements PlaySessionsApi {
  final sent = <List<PlaySessionRecord>>[];
  bool fail = false;
  PlayTime? remote;

  @override
  Future<void> record(List<PlaySessionRecord> sessions) async {
    if (fail) throw StateError('offline');
    sent.add(sessions);
  }

  @override
  Future<PlayTime?> timeFor(String gameId) async => remote;

  @override
  Future<List<RemoteSession>?> sessionsSince(DateTime since) async => null;
}

void main() {
  late PlayTimeLog log;
  late ProfilePreferences prefs;
  setUp(() async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).delete(recursive: true));
    final paths = ProfilePaths(root, 'anna');
    io.Directory(paths.dir).createSync(recursive: true);
    prefs = ProfilePreferences.open(paths);
    log = PlayTimeLog(prefs);
  });

  PlaySessionRecord s(String game, int minutes, {int at = 0}) {
    final start = DateTime.utc(2026, 10, 24, 12).add(Duration(hours: at));
    return PlaySessionRecord(
      gameId: game,
      start: start,
      end: start.add(Duration(minutes: minutes)),
    );
  }

  test("kept until RomM has them; a failure keeps them for the next game", () async {
    final api = _FakeApi()..fail = true;
    await log.add(s('1', 30));
    await log.add(s('2', 10, at: 1));
    await log.sendUnsent(api);
    expect(log.unsent.length, 2);
    api.fail = false;
    await log.sendUnsent(api);
    expect(api.sent.single.map((x) => x.gameId), ['1', '2']);
    expect(log.unsent, isEmpty);
    expect(log.all.length, 2, reason: 'kept, as sent');
    expect(log.timeFor('1').total, const Duration(minutes: 30));
  });

  test("RomM's time with this PC's not yet sent; this PC's alone when RomM has none", () async {
    final api = _FakeApi()..remote = const PlayTime(Duration(hours: 2), 3);
    await log.add(s('1', 30));
    final c = ProviderContainer(
      overrides: [playTimeLogProvider.overrideWithValue(log), playSessionsApiProvider.overrideWithValue(api)],
    );
    addTearDown(c.dispose);
    final both = await c.read(playTimeProvider('1').future);
    expect((both!.total, both.sessions, both.thisPcOnly), (const Duration(hours: 2, minutes: 30), 4, false));
    api.remote = null;
    c.invalidate(playTimeProvider('1'));
    final local = await c.read(playTimeProvider('1').future);
    expect((local!.total, local.thisPcOnly), (const Duration(minutes: 30), true));
    expect(await c.read(playTimeProvider('9').future), isNull, reason: 'never played');
  });

  test("RomM's sessions: sent without a device id, summed when read; none on an older RomM", () async {
    final a = FakeDioAdapter(
      (r) => r.method == 'GET'
          ? (
              status: 200,
              body: [
                {'duration_ms': 60000},
                {'duration_ms': 120000},
              ],
            )
          : (status: 201, body: {'created_count': 1}),
    );
    final api = RommPlaySessions(fakeDio(a), Options.new);
    await api.record([s('7', 5)]);
    final body = a.requests.first.data as Map;
    expect(body.containsKey('device_id'), isFalse);
    expect((body['sessions'] as List).single, {
      'rom_id': 7,
      'start_time': '2026-10-24T12:00:00.000Z',
      'end_time': '2026-10-24T12:05:00.000Z',
      'duration_ms': 300000,
    });
    final t = await api.timeFor('7');
    expect((t!.total, t.sessions), (const Duration(minutes: 3), 2));
    expect(a.requests.last.queryParameters['rom_id'], '7');
    final old = RommPlaySessions(fakeDio(FakeDioAdapter((r) => (status: 404, body: {}))), Options.new);
    expect(await old.timeFor('7'), isNull);
  });

  test("sent with this PC's device id once it has one", () async {
    final a = FakeDioAdapter((r) => (status: 201, body: {'created_count': 1}));
    await RommPlaySessions(fakeDio(a), Options.new, deviceId: () => 'pc-1').record([s('7', 5)]);
    expect((a.requests.single.data as Map)['device_id'], 'pc-1');
  });

  test('the line', () {
    expect(formatPlayTime(const Duration(seconds: 20)), 'under a minute');
    expect(formatPlayTime(const Duration(minutes: 35)), '35 min');
    expect(formatPlayTime(const Duration(hours: 12, minutes: 40)), '12 h 40 min');
    expect(formatPlayTime(const Duration(hours: 3)), '3 h');
    expect(
      playTimeLine(const PlayTime(Duration(minutes: 35), 1, thisPcOnly: true)),
      'Played 35 min · 1 session on this PC',
    );
  });
}
