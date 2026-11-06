part of '../romm_service.dart';

/// Games sent to this PC from RomM's web page (#288, RomM 5.4's device
/// installs).
mixin _RommInstalls on _RommBase {
  /// Takes every request waiting for [deviceId] and gives all it holds
  /// (`POST /api/devices/{id}/installs/claim`). A claim also shows the
  /// device as online in RomM for 90 s. Throws when RomM can't be reached.
  Future<InstallClaim> claimInstalls(String deviceId) async {
    final r = await _dio.post<dynamic>(
      '/api/devices/${Uri.encodeComponent(deviceId)}/installs/claim',
      options: _authOptions.copyWith(validateStatus: (s) => s != null && s < 500),
    );
    final status = r.statusCode ?? 0;
    if (status == 403) return const InstallsNotBound();
    if (status == 404) return const InstallsOff();
    if (status < 200 || status >= 300) throw StateError('RomM answered a claim with $status');
    final data = r.data;
    return InstallsTaken([
      if (data is List)
        for (final item in data) ?InstallRequest.fromJson(item),
    ]);
  }

  /// Tells RomM how request [requestId] ended
  /// (`PUT /api/devices/{id}/installs/{request}`). A request RomM no longer
  /// has, or has ended (404, 409), counts as told. Throws when RomM can't be
  /// reached or refuses it otherwise.
  Future<void> reportInstall(String deviceId, String requestId, InstallOutcome outcome, {String? reason}) async {
    final why = reason == null || reason.length <= installReasonMax ? reason : reason.substring(0, installReasonMax);
    final r = await _dio.put<dynamic>(
      '/api/devices/${Uri.encodeComponent(deviceId)}/installs/${Uri.encodeComponent(requestId)}',
      data: {'status': outcome.name, 'reason': ?why},
      options: _authOptions.copyWith(contentType: 'application/json', validateStatus: (s) => s != null && s < 500),
    );
    final status = r.statusCode ?? 0;
    if (status == 404 || status == 409) return;
    if (status < 200 || status >= 300) throw StateError('RomM answered an install report with $status');
  }

  /// Says whether [deviceId] takes games sent from RomM's web page
  /// (`PUT /api/devices/{id}` with `capabilities.remote_install`): RomM offers
  /// only devices that do. False when RomM didn't take it.
  Future<bool> setRemoteInstall(String deviceId, bool on) async {
    try {
      final r = await _dio.put<dynamic>(
        '/api/devices/${Uri.encodeComponent(deviceId)}',
        data: {
          'capabilities': {'remote_install': on},
        },
        options: _authOptions.copyWith(contentType: 'application/json', validateStatus: (s) => s != null && s < 500),
      );
      final status = r.statusCode ?? 0;
      return status >= 200 && status < 300;
    } catch (e) {
      debugPrint('[RomM] setRemoteInstall error: $e');
      return false;
    }
  }
}
