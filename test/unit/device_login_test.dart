import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_auth_client.dart';
import 'package:gargosy/profiles/device_login.dart';

import '../helpers/fake_romm_auth.dart';

void main() {
  const start = DeviceAuthStart(deviceCode: 'dc', userCode: 'U', verificationUrl: 'u', expiresIn: 60, interval: 5);

  test('polls at the interval until approved', () async {
    final waits = <Duration>[];
    final auth = FakeRommAuth(polls: [const DevicePending(), const DevicePending(), const DeviceApproved(token: 't', deviceId: 'd')]);
    final result = await DeviceLoginFlow(auth, start, delay: (d) async => waits.add(d)).run();
    expect(result, isA<DeviceApproved>());
    expect(waits, List.filled(3, const Duration(seconds: 5)));
  });

  test('slow_down adds five seconds to the interval', () async {
    final waits = <Duration>[];
    final auth = FakeRommAuth(polls: [const DeviceSlowDown(), const DeviceApproved(token: 't', deviceId: 'd')]);
    await DeviceLoginFlow(auth, start, delay: (d) async => waits.add(d)).run();
    expect(waits, [const Duration(seconds: 5), const Duration(seconds: 10)]);
  });

  test('flow keeps polling through a network error', () async {
    final auth = FakeRommAuth(polls: [
      const RommAuthException(RommAuthFailure.network, 'offline'),
      const DeviceApproved(token: 't', deviceId: 'd'),
    ]);
    expect(await DeviceLoginFlow(auth, start, delay: (_) async {}).run(), isA<DeviceApproved>());
  });

  test('denied stops the flow', () async {
    final auth = FakeRommAuth(polls: [const DeviceDenied()]);
    expect(await DeviceLoginFlow(auth, start, delay: (_) async {}).run(), isA<DeviceDenied>());
  });

  test('expires when the code runs out, without asking the server again', () async {
    var now = DateTime(2026);
    final auth = FakeRommAuth(polls: List.filled(100, const DevicePending()));
    final flow = DeviceLoginFlow(auth, start, delay: (d) async => now = now.add(d), now: () => now);
    expect(await flow.run(), isA<DeviceExpired>());
    expect(auth.pollCount, lessThanOrEqualTo(12));
  });

  test('cancel stops the flow', () async {
    final auth = FakeRommAuth(polls: List.filled(100, const DevicePending()));
    late DeviceLoginFlow flow;
    flow = DeviceLoginFlow(auth, start, delay: (_) async => flow.cancel());
    expect(await flow.run(), isA<DeviceCancelled>());
    expect(auth.pollCount, 0);
  });
}
