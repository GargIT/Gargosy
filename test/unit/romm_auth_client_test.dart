import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_auth_client.dart';

import '../helpers/fake_dio_adapter.dart';

const meJson = {
  'id': 7,
  'username': 'anna',
  'avatar_path': 'users/7/avatar.png',
  'oauth_scopes': ['me.read', 'me.write', 'roms.read', 'roms.user.read', 'roms.user.write', 'platforms.read',
    'assets.read', 'assets.write', 'devices.read', 'devices.write', 'firmware.read', 'collections.read', 'collections.write'],
};

void main() {
  RommAuthClient client(FakeDioAdapter a) => RommAuthClient('https://romm.example', dio: fakeDio(a));

  test('normalizeBaseUrl trims, drops the trailing slash and adds https', () {
    expect(RommAuthClient.normalizeBaseUrl(' romm.example/ '), 'https://romm.example');
    expect(RommAuthClient.normalizeBaseUrl('http://10.0.0.5:8080/'), 'http://10.0.0.5:8080');
  });

  test('startDeviceAuth posts the device and Gargosy\'s scopes and builds the QR url', () async {
    final a = FakeDioAdapter((r) => (status: 201, body: {
          'device_code': 'dc', 'user_code': 'ABCD-1234', 'verification_path': '/pair/device',
          'verification_path_complete': '/pair/device?user_code=ABCD-1234', 'expires_in': 600, 'interval': 5,
        }));
    final start = await client(a).startDeviceAuth(deviceIdentifier: 'id-1', deviceName: 'Gargosy on LIVINGROOM');
    expect(start!.userCode, 'ABCD-1234');
    expect(start.verificationUrl, 'https://romm.example/pair/device?user_code=ABCD-1234');
    expect(start.interval, 5);
    final sent = a.requests.single;
    expect(sent.path, '/api/auth/device/init');
    expect(sent.data['client'], 'Gargosy');
    expect(sent.data['requested_scopes'], gargosyScopes);
  });

  test('startDeviceAuth returns null on 404 (server without device pairing)', () async {
    final a = FakeDioAdapter((r) => (status: 404, body: {'detail': 'Not Found'}));
    expect(await client(a).startDeviceAuth(deviceIdentifier: 'i', deviceName: 'n'), isNull);
  });

  test('startDeviceAuth on an unreachable server is a network failure', () async {
    final a = FakeDioAdapter((r) => (status: -1, body: null));
    expect(() => client(a).startDeviceAuth(deviceIdentifier: 'i', deviceName: 'n'),
        throwsA(isA<RommAuthException>().having((e) => e.failure, 'failure', RommAuthFailure.network)));
  });

  test('pollDeviceAuth maps every server answer', () async {
    Future<DevicePoll> poll(int status, Object body) =>
        client(FakeDioAdapter((r) => (status: status, body: body))).pollDeviceAuth('dc');
    expect(await poll(400, {'detail': 'authorization_pending'}), isA<DevicePending>());
    expect(await poll(400, {'detail': 'slow_down'}), isA<DeviceSlowDown>());
    expect(await poll(429, {'detail': 'Too many requests'}), isA<DeviceSlowDown>());
    expect(await poll(400, {'detail': 'access_denied'}), isA<DeviceDenied>());
    expect(await poll(400, {'detail': 'expired_token'}), isA<DeviceExpired>());
    final ok = await poll(200, {'access_token': 'rmm_x', 'device_id': 'd9', 'scopes': ['me.read']});
    expect(ok, isA<DeviceApproved>().having((x) => x.token, 'token', 'rmm_x').having((x) => x.deviceId, 'device', 'd9'));
  });

  test('password login asks for the user with Basic auth, then creates a never-expiring client token', () async {
    final a = FakeDioAdapter((r) {
      if (r.path == '/api/users/me') return (status: 200, body: meJson);
      if (r.path == '/api/client-tokens') return (status: 201, body: {'raw_token': 'rmm_new', 'id': 3});
      return (status: 500, body: null);
    });
    final token = await client(a).loginWithPassword(username: 'anna', password: 'pw', tokenName: 'Gargosy on PC');
    expect(token, 'rmm_new');
    final basic = 'Basic ${base64Encode(utf8.encode('anna:pw'))}';
    expect(a.requests.map((r) => r.headers['Authorization']), everyElement(basic));
    final create = a.requests.last;
    expect(create.data['name'], 'Gargosy on PC');
    expect(create.data['scopes'], gargosyScopes);
    expect(create.data.containsKey('expires_in'), isTrue);
    expect(create.data['expires_in'], isNull);
  });

  test('password login only asks for scopes the user has', () async {
    final a = FakeDioAdapter((r) => r.path == '/api/users/me'
        ? (status: 200, body: {...meJson, 'oauth_scopes': ['me.read', 'me.write', 'roms.read', 'platforms.read']})
        : (status: 201, body: {'raw_token': 't'}));
    await client(a).loginWithPassword(username: 'u', password: 'p', tokenName: 'n');
    expect(a.requests.last.data['scopes'], ['me.read', 'me.write', 'roms.read', 'platforms.read']);
  });

  test('a wrong password is badCredentials', () async {
    final a = FakeDioAdapter((r) => (status: 401, body: {'detail': 'Invalid'}));
    expect(() => client(a).loginWithPassword(username: 'u', password: 'p', tokenName: 'n'),
        throwsA(isA<RommAuthException>().having((e) => e.failure, 'failure', RommAuthFailure.badCredentials)));
  });

  test('password login on a server without client tokens says it is too old', () async {
    final a = FakeDioAdapter((r) => r.path == '/api/users/me' ? (status: 200, body: meJson) : (status: 404, body: {}));
    expect(() => client(a).loginWithPassword(username: 'u', password: 'p', tokenName: 'n'),
        throwsA(isA<RommAuthException>().having((e) => e.failure, 'failure', RommAuthFailure.serverTooOld)));
  });

  test('a user without me.write cannot create a token: insufficientScope', () async {
    final a = FakeDioAdapter((r) => (status: 200, body: {...meJson, 'oauth_scopes': ['roms.read']}));
    expect(() => client(a).loginWithPassword(username: 'u', password: 'p', tokenName: 'n'),
        throwsA(isA<RommAuthException>().having((e) => e.failure, 'failure', RommAuthFailure.insufficientScope)));
  });

  test('fetchMe sends the token as Bearer', () async {
    final a = FakeDioAdapter((r) => (status: 200, body: meJson));
    final me = await client(a).fetchMe('rmm_t');
    expect(me.id, 7);
    expect(me.username, 'anna');
    expect(a.requests.single.headers['Authorization'], 'Bearer rmm_t');
  });

  test('fetchAvatar returns the bytes, or null when there is none', () async {
    final ok = FakeDioAdapter((r) => (status: 200, body: <int>[137, 80, 78, 71]));
    expect(await client(ok).fetchAvatar('t', 7), [137, 80, 78, 71]);
    expect(ok.requests.single.path, '/api/users/7/avatar');
    final none = FakeDioAdapter((r) => (status: 404, body: {'detail': 'Avatar not found'}));
    expect(await client(none).fetchAvatar('t', 7), isNull);
  });

  test('the auth client never follows redirects with the password', () {
    final c = RommAuthClient('https://romm.example');
    expect(c.dioForTest.options.followRedirects, isFalse);
    expect(c.dioForTest.options.validateStatus(302), isFalse);
    expect(Dio().options.followRedirects, isTrue); // sanity: default differs
  });
}
