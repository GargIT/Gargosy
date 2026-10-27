import 'package:dio/dio.dart';

/// One player's game right now on RomM (#180), from `GET /api/activity`:
/// kept alive by the heartbeats of whatever plays it (Gargosy sends them
/// while a game runs), gone 90 s after the last.
class ActivityEntry {
  const ActivityEntry({
    required this.userId,
    required this.username,
    required this.gameId,
    required this.gameName,
    required this.platformName,
    required this.deviceId,
    required this.client,
    required this.startedAt,
    this.coverPath = '',
    this.screenshotPath = '',
  });

  /// Null for an entry without the fields RomM always sends.
  static ActivityEntry? fromJson(Object? json) {
    if (json is! Map || json['user_id'] is! int || json['rom_id'] is! int) return null;
    String text(String key) => json[key] is String ? json[key] as String : '';
    final started = DateTime.tryParse(text('started_at'));
    if (started == null) return null;
    return ActivityEntry(
      userId: json['user_id'] as int,
      username: text('username'),
      gameId: '${json['rom_id']}',
      gameName: text('rom_name'),
      platformName: text('platform_name'),
      deviceId: text('device_id'),
      client: text('device_type'),
      startedAt: started.toUtc(),
      coverPath: text('rom_cover_path'),
      screenshotPath: text('screenshot_path'),
    );
  }

  final int userId;
  final String username;
  final String gameId;
  final String gameName;
  final String platformName;
  final String deviceId;

  /// What it plays on, as the device registered with RomM: `Gargosy`,
  /// `web`, `argosy-launcher`, `streaming`…
  final String client;
  final DateTime startedAt;

  /// RomM paths (`/assets/romm/…`); empty when there is none.
  final String coverPath;

  /// The player's latest save screenshot, else the title screen.
  final String screenshotPath;
}

/// RomM's activity board (#180); the seam tests fake.
abstract interface class ActivityApi {
  /// Everyone playing now, oldest first; none from a RomM without it.
  Future<List<ActivityEntry>> playingNow();
}

class RommActivity implements ActivityApi {
  RommActivity(this._dio, this._auth);

  final Dio _dio;
  final Options Function() _auth;

  @override
  Future<List<ActivityEntry>> playingNow() async {
    final Response<dynamic> r;
    try {
      r = await _dio.get('/api/activity', options: _auth());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const [];
      rethrow;
    }
    return [for (final e in r.data is List ? r.data as List : const []) ?ActivityEntry.fromJson(e)]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }
}

/// Where [entry] plays, as a card says it: this PC when it's this profile's
/// device here, else by the client.
String activityWhere(ActivityEntry entry, {String? thisDeviceId}) {
  if (thisDeviceId != null && entry.deviceId == thisDeviceId) return 'on this PC';
  return switch (entry.client.toLowerCase()) {
    'gargosy' => 'on Gargosy',
    'web' => "in RomM's web UI",
    'streaming' => 'streamed by RomM',
    '' || 'unknown' => 'on RomM',
    _ => 'on ${entry.client}',
  };
}

/// How long [entry] has been played at [now]: `for 4 min`, `for 1 h 10 min`.
String activityFor(ActivityEntry entry, DateTime now) {
  final minutes = now.toUtc().difference(entry.startedAt).inMinutes;
  if (minutes < 1) return 'just started';
  if (minutes < 60) return 'for $minutes min';
  final rest = minutes % 60;
  return rest == 0 ? 'for ${minutes ~/ 60} h' : 'for ${minutes ~/ 60} h $rest min';
}
