import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_activity.dart';

import '../helpers/fake_dio_adapter.dart';

void main() {
  Map<String, dynamic> entry(int user, String game, String started, {String client = 'Gargosy'}) => {
    'user_id': user,
    'username': 'user$user',
    'avatar_path': user == 1 ? 'users/1/profile/avatar.png' : '',
    'rom_id': 40 + user,
    'rom_name': game,
    'rom_cover_path': 'roms/1/$user/cover/small.png',
    'screenshot_path': '',
    'platform_slug': 'snes',
    'platform_name': 'Super Nintendo',
    'device_id': 'dev$user',
    'device_type': client,
    'started_at': started,
  };

  test("RomM's activity, oldest first; broken entries left out; none from an older RomM", () async {
    final a = FakeDioAdapter(
      (_) => (
        status: 200,
        body: [
          entry(2, 'Kirby', '2026-10-27T10:20:00+00:00'),
          {'user_id': 'x'},
          entry(1, 'Super Metroid', '2026-10-27T09:55:00+00:00'),
        ],
      ),
    );
    final now = await RommActivity(fakeDio(a), () => Options()).playingNow();
    expect([for (final e in now) e.gameName], ['Super Metroid', 'Kirby']);
    expect(now.first.gameId, '41');
    expect(now.first.platformName, 'Super Nintendo');
    expect(now.first.coverPath, '/assets/romm/resources/roms/1/1/cover/small.png', reason: 'RomM sends it bare');
    expect(now.first.avatarPath, 'users/1/profile/avatar.png');
    expect(now.last.avatarPath, isEmpty);
    expect(a.requests.single.path, '/api/activity');
    final old = FakeDioAdapter((_) => (status: 404, body: <String, dynamic>{}));
    expect(await RommActivity(fakeDio(old), () => Options()).playingNow(), isEmpty);
  });

  test('where a game is played, and for how long', () {
    final e = ActivityEntry.fromJson(entry(1, 'Super Metroid', '2026-10-27T09:00:00Z'))!;
    expect(activityWhere(e, thisDeviceId: 'dev1'), 'on this PC');
    expect(activityWhere(e, thisDeviceId: 'other'), 'on Gargosy');
    expect(
      activityWhere(ActivityEntry.fromJson(entry(1, 'x', '2026-10-27T09:00:00Z', client: 'web'))!),
      "in RomM's web UI",
    );
    expect(activityWhere(ActivityEntry.fromJson(entry(1, 'x', '2026-10-27T09:00:00Z', client: 'grout'))!), 'on grout');
    expect(activityFor(e, DateTime.utc(2026, 10, 27, 9, 0, 30)), 'just started');
    expect(activityFor(e, DateTime.utc(2026, 10, 27, 9, 25)), 'for 25 min');
    expect(activityFor(e, DateTime.utc(2026, 10, 27, 10)), 'for 1 h');
    expect(activityFor(e, DateTime.utc(2026, 10, 27, 10, 10)), 'for 1 h 10 min');
  });
}
