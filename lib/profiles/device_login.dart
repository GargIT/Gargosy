import '../core/romm/romm_auth_client.dart';

/// Polls a started device pairing until the user approves or denies it on
/// their phone, the code expires, or [cancel] is called.
class DeviceLoginFlow {
  DeviceLoginFlow(this.auth, this.start, {Future<void> Function(Duration)? delay, DateTime Function()? now})
    : _delay = delay ?? Future<void>.delayed,
      _now = now ?? DateTime.now;

  final RommAuth auth;
  final DeviceAuthStart start;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Future<DevicePoll> run() async {
    // Never faster than once a second, whatever the server says.
    var interval = Duration(seconds: start.interval < 1 ? 1 : start.interval);
    final deadline = _now().add(Duration(seconds: start.expiresIn));
    while (true) {
      await _delay(interval);
      if (_cancelled) return const DeviceCancelled();
      if (!_now().isBefore(deadline)) return const DeviceExpired();
      final DevicePoll result;
      try {
        result = await auth.pollDeviceAuth(start.deviceCode);
      } on RommAuthException catch (e) {
        if (e.failure == RommAuthFailure.network || e.failure == RommAuthFailure.server) continue;
        rethrow;
      }
      switch (result) {
        case DevicePending():
          continue;
        case DeviceSlowDown():
          interval += const Duration(seconds: 5);
          continue;
        default:
          return result;
      }
    }
  }
}
