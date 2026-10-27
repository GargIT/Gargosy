// Adapted from Freegosy (MIT, © 2026 abduznik).
part of '../romm_service.dart';

/// Play sessions and the activity heartbeat.
mixin _RommPlay on _RommBase {
  // ---------------------------------------------------------------------------
  // Play session tracking (RomM 4.9+)
  // ---------------------------------------------------------------------------

  /// Records a completed play session with the server.
  ///
  /// Called after the emulator process exits on 4.9+ servers only.
  /// Silently no-ops on errors — play time tracking is best-effort.
  ///
  /// [romId]      — the game's RomM ID
  /// [deviceId]   — this device's registered UUID
  /// [startTime]  — when the emulator was launched
  /// [endTime]    — when the emulator process exited
  Future<void> recordPlaySession({
    required String romId,
    required String deviceId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      final id = int.tryParse(romId);
      if (id == null) return;

      final durationMs = endTime.difference(startTime).inMilliseconds;
      if (durationMs <= 0) return;

      await _dio.post(
        '/api/play-sessions',
        data: {
          'device_id': deviceId,
          'sessions': [
            {
              'rom_id': id,
              'start_time': startTime.toUtc().toIso8601String(),
              'end_time': endTime.toUtc().toIso8601String(),
              'duration_ms': durationMs,
            },
          ],
        },
        options: _authOptions.copyWith(contentType: 'application/json'),
      );
      debugPrint('[RomM] Recorded play session for rom $romId: ${durationMs}ms');
    } catch (e) {
      debugPrint('[RomM] recordPlaySession error (non-fatal): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Active session heartbeat (RomM 4.9+, issue #93)
  // ---------------------------------------------------------------------------

  /// Pings RomM's real-time "active sessions" board so other clients (the
  /// web UI, dashboard integrations, etc.) see this device as currently
  /// playing [romId]. Call once on launch, then repeat periodically while
  /// the game is running — the server expires the entry ~90s after the last
  /// heartbeat. Silently no-ops on errors; this is cosmetic only.
  Future<void> sendActivityHeartbeat({required String romId, required String deviceId}) async {
    final id = int.tryParse(romId);
    if (id == null) {
      debugPrint('[RomM] sendActivityHeartbeat skipped: romId "$romId" is not numeric');
      return;
    }
    try {
      await _dio.post(
        '/api/activity/heartbeat',
        data: {'rom_id': id, 'device_id': deviceId},
        options: _authOptions.copyWith(
          contentType: 'application/json',
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      debugPrint('[RomM] sendActivityHeartbeat ok (rom $id, device $deviceId)');
    } catch (e) {
      debugPrint('[RomM] sendActivityHeartbeat error (non-fatal): $e');
    }
  }

  /// Immediately clears this device's active session (e.g. on game exit),
  /// rather than waiting out the server's heartbeat TTL. Silently no-ops on
  /// errors; this is cosmetic only.
  Future<void> clearActivityHeartbeat({required String deviceId}) async {
    try {
      await _dio.delete(
        '/api/activity/heartbeat',
        queryParameters: {'device_id': deviceId},
        options: _authOptions.copyWith(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      debugPrint('[RomM] clearActivityHeartbeat ok (device $deviceId)');
    } catch (e) {
      debugPrint('[RomM] clearActivityHeartbeat error (non-fatal): $e');
    }
  }
}
