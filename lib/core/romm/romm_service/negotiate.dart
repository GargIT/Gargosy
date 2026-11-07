part of '../romm_service.dart';

/// RomM's sync negotiation (#294), asked only to compare with what Gargosy
/// does (docs/negotiate-sync.md).
mixin _RommNegotiate on _RommBase {
  /// Asks RomM what it would do with [saves] of device [deviceId]
  /// (`POST /api/sync/negotiate`). Null when RomM has no negotiate (a 404:
  /// older than 5.4). Throws when RomM can't be reached or refuses.
  Future<NegotiateResult?> negotiateSync({
    required String deviceId,
    required List<NegotiateSave> saves,
    required List<String> romIds,
    bool restoreUnlisted = false,
    List<String>? emulators,
  }) async {
    final r = await _dio.post<dynamic>(
      '/api/sync/negotiate',
      data: {
        'device_id': deviceId,
        'saves': [for (final s in saves) s.toJson()],
        'rom_ids': [for (final id in romIds) int.tryParse(id) ?? id],
        'restore_unlisted': restoreUnlisted,
        'emulators': ?emulators,
      },
      options: _authOptions.copyWith(contentType: 'application/json', validateStatus: (s) => s != null && s < 500),
    );
    final status = r.statusCode ?? 0;
    if (status == 404) return null;
    final data = r.data;
    if (status < 200 || status >= 300 || data is! Map || data['session_id'] is! int) {
      throw StateError('RomM answered negotiate with $status');
    }
    final ops = data['operations'];
    return NegotiateResult(data['session_id'] as int, [
      if (ops is List)
        for (final op in ops) ?SyncOperation.fromJson(op),
    ]);
  }

  /// Closes negotiate's session [sessionId]
  /// (`POST /api/sync/sessions/{id}/complete`). Never throws.
  Future<void> completeSync(int sessionId, {int completed = 0, int failed = 0}) async {
    try {
      await _dio.post<dynamic>(
        '/api/sync/sessions/$sessionId/complete',
        data: {'operations_completed': completed, 'operations_failed': failed},
        options: _authOptions.copyWith(contentType: 'application/json'),
      );
    } catch (e) {
      debugPrint('[RomM] completeSync $sessionId error: $e');
    }
  }
}
