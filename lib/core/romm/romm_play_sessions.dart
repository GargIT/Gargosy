import 'package:dio/dio.dart';

/// One session of a game: when it started and ended (#146).
class PlaySessionRecord {
  const PlaySessionRecord({required this.gameId, required this.start, required this.end, this.sent = false});

  final String gameId;
  final DateTime start;
  final DateTime end;

  /// RomM has it.
  final bool sent;

  Duration get length => end.difference(start);

  PlaySessionRecord asSent() => PlaySessionRecord(gameId: gameId, start: start, end: end, sent: true);

  Map<String, Object?> toJson() => {
    'game': gameId,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    if (sent) 'sent': true,
  };

  static PlaySessionRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final start = DateTime.tryParse('${json['start']}');
    final end = DateTime.tryParse('${json['end']}');
    final game = json['game'];
    if (start == null || end == null || game is! String) return null;
    return PlaySessionRecord(gameId: game, start: start, end: end, sent: json['sent'] == true);
  }
}

/// A game's time played: in all, and in how many sessions.
class PlayTime {
  const PlayTime(this.total, this.sessions, {this.thisPcOnly = false});

  final Duration total;
  final int sessions;

  /// Counted from this PC's sessions only (RomM before 5.4, or offline).
  final bool thisPcOnly;
}

/// RomM 5.4's play sessions (`/api/play-sessions`, #146): sent after a
/// game, and read back for a game's time played on every device.
abstract class PlaySessionsApi {
  /// Sends [sessions] (at most [batch]); throws when RomM didn't take them.
  Future<void> record(List<PlaySessionRecord> sessions);

  /// [gameId]'s sessions on RomM, from every device; null when this RomM
  /// has no play sessions.
  Future<PlayTime?> timeFor(String gameId);

  static const batch = 100;
}

class RommPlaySessions implements PlaySessionsApi {
  RommPlaySessions(this.dio, this.auth);

  final Dio dio;
  final Options Function() auth;

  @override
  Future<void> record(List<PlaySessionRecord> sessions) async {
    if (sessions.isEmpty) return;
    // No device id: RomM takes the one the login is paired with, if any.
    await dio.post(
      '/api/play-sessions',
      data: {
        'sessions': [
          for (final s in sessions.take(PlaySessionsApi.batch))
            {
              'rom_id': ?int.tryParse(s.gameId),
              'start_time': s.start.toUtc().toIso8601String(),
              'end_time': s.end.toUtc().toIso8601String(),
              'duration_ms': s.length.inMilliseconds,
            },
        ],
      },
      options: auth().copyWith(contentType: 'application/json'),
    );
  }

  @override
  Future<PlayTime?> timeFor(String gameId) async {
    final Response<dynamic> r;
    try {
      r = await dio.get('/api/play-sessions', queryParameters: {'rom_id': gameId, 'limit': 10000}, options: auth());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
    final list = r.data is List ? r.data as List : const [];
    var ms = 0;
    for (final s in list) {
      if (s is Map && s['duration_ms'] is int) ms += s['duration_ms'] as int;
    }
    return PlayTime(Duration(milliseconds: ms), list.length);
  }
}
