import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// The RomM scopes Gargosy asks for (spec §5). Admin scopes are never asked for.
const gargosyScopes = [
  'me.read', 'me.write',
  'roms.read', 'roms.user.read', 'roms.user.write',
  'platforms.read',
  'assets.read', 'assets.write',
  'devices.read', 'devices.write',
  'firmware.read',
  'collections.read', 'collections.write',
];

class RommUser {
  const RommUser({required this.id, required this.username, required this.avatarPath, required this.oauthScopes});

  final int id;
  final String username;
  final String avatarPath;
  final List<String> oauthScopes;

  factory RommUser.fromJson(Map<String, dynamic> json) => RommUser(
        id: json['id'] as int,
        username: json['username'] as String,
        avatarPath: json['avatar_path'] as String? ?? '',
        oauthScopes: [for (final s in (json['oauth_scopes'] as List? ?? const [])) s as String],
      );
}

class DeviceAuthStart {
  const DeviceAuthStart({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;

  /// `<server>/pair/device?user_code=…`, for the QR code.
  final String verificationUrl;
  final int expiresIn;
  final int interval;
}

sealed class DevicePoll {
  const DevicePoll();
}

class DevicePending extends DevicePoll {
  const DevicePending();
}

class DeviceSlowDown extends DevicePoll {
  const DeviceSlowDown();
}

class DeviceDenied extends DevicePoll {
  const DeviceDenied();
}

class DeviceExpired extends DevicePoll {
  const DeviceExpired();
}

class DeviceCancelled extends DevicePoll {
  const DeviceCancelled();
}

class DeviceApproved extends DevicePoll {
  const DeviceApproved({required this.token, required this.deviceId});
  final String token;
  final String deviceId;
}

enum RommAuthFailure {
  badCredentials,
  serverTooOld,
  insufficientScope,
  network,

  /// 5xx or 408: RomM (or the proxy in front of it) failed for now; worth retrying.
  server,

  /// The answer isn't RomM's (a web page, a missing field): probably the wrong address.
  notRomm,

  /// Logged in as another RomM user than the profile's; [RommAuthException.message] is that username.
  wrongUser,
  other,
}

class RommAuthException implements Exception {
  const RommAuthException(this.failure, this.message);
  final RommAuthFailure failure;
  final String message;

  @override
  String toString() => 'RommAuthException(${failure.name}): $message';
}

/// Logging in to RomM. [RommAuthClient] is the real one; tests use a fake.
abstract class RommAuth {
  /// Starts device pairing; null when the server doesn't have it.
  Future<DeviceAuthStart?> startDeviceAuth({required String deviceIdentifier, required String deviceName});
  Future<DevicePoll> pollDeviceAuth(String deviceCode);

  /// Logs in with a password once and returns a long-lived client token.
  ///
  /// With [expectedUserId], another RomM user is refused (`wrongUser`) before
  /// any token is made.
  Future<String> loginWithPassword(
      {required String username, required String password, required String tokenName, int? expectedUserId});
  Future<RommUser> fetchMe(String token);
  Future<Uint8List?> fetchAvatar(String token, int userId);
}

class RommAuthClient implements RommAuth {
  RommAuthClient(String baseUrl, {Dio? dio, bool trustSelfSigned = false})
      : baseUrl = normalizeBaseUrl(baseUrl),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'User-Agent': 'Gargosy', 'Accept': 'application/json'},
              // A redirect could carry the Basic header to another host.
              followRedirects: false,
              validateStatus: (s) => s != null && s >= 200 && s < 300,
            )) {
    _dio.options.baseUrl = this.baseUrl;
    if (dio == null && trustSelfSigned) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => io.HttpClient()..badCertificateCallback = (cert, host, port) => true,
      );
    }
  }

  final String baseUrl;
  final Dio _dio;

  @visibleForTesting
  Dio get dioForTest => _dio;

  static String normalizeBaseUrl(String url) {
    var u = url.trim();
    if (!u.contains('://')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// Reads a RomM answer with [read]; anything that isn't the JSON RomM sends
  /// (a web page, a missing field) is [RommAuthFailure.notRomm].
  static T _parse<T>(Object? data, T Function(Map<String, dynamic> json) read) {
    try {
      if (data is! Map<String, dynamic>) throw const FormatException();
      return read(data);
    } on Object catch (e) {
      if (e is RommAuthException) rethrow;
      throw const RommAuthException(RommAuthFailure.notRomm, 'This does not look like a RomM server');
    }
  }

  static Options _bearer(String token) => Options(headers: {'Authorization': 'Bearer $token'});

  static Never _fail(DioException e, {RommAuthFailure on404 = RommAuthFailure.other}) {
    final status = e.response?.statusCode;
    if (status == null) throw RommAuthException(RommAuthFailure.network, e.message ?? 'The server could not be reached');
    if (status == 401) throw const RommAuthException(RommAuthFailure.badCredentials, 'Wrong username or password');
    if (status == 404 || status == 405) throw RommAuthException(on404, 'The server does not support this');
    if (status >= 500 || status == 408) throw RommAuthException(RommAuthFailure.server, 'RomM answered $status');
    final detail = e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
    throw RommAuthException(RommAuthFailure.other, 'RomM answered $status${detail != null ? ': $detail' : ''}');
  }

  @override
  Future<DeviceAuthStart?> startDeviceAuth({required String deviceIdentifier, required String deviceName}) async {
    try {
      final r = await _dio.post('/api/auth/device/init', data: {
        'client_device_identifier': deviceIdentifier,
        'name': deviceName,
        'client': 'Gargosy',
        'platform': 'windows',
        'requested_scopes': gargosyScopes,
      });
      return _parse<DeviceAuthStart>(r.data, (d) => DeviceAuthStart(
            deviceCode: d['device_code'] as String,
            userCode: d['user_code'] as String,
            verificationUrl: '$baseUrl${d['verification_path_complete'] as String}',
            expiresIn: d['expires_in'] as int,
            interval: d['interval'] as int,
          ));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404 || status == 405) return null;
      _fail(e);
    }
  }

  @override
  Future<DevicePoll> pollDeviceAuth(String deviceCode) async {
    try {
      final r = await _dio.post('/api/auth/device/token', data: {'device_code': deviceCode});
      return _parse<DevicePoll>(r.data, (d) => DeviceApproved(token: d['access_token'] as String, deviceId: d['device_id'] as String));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 429) return const DeviceSlowDown();
      final detail = e.response?.data is Map ? (e.response!.data as Map)['detail'] : null;
      if (status == 400) {
        switch (detail) {
          case 'authorization_pending':
            return const DevicePending();
          case 'slow_down':
            return const DeviceSlowDown();
          case 'access_denied':
            return const DeviceDenied();
          case 'expired_token':
            return const DeviceExpired();
        }
      }
      _fail(e);
    }
  }

  @override
  Future<String> loginWithPassword(
      {required String username, required String password, required String tokenName, int? expectedUserId}) async {
    final basic = Options(headers: {'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}'});
    final RommUser me;
    try {
      me = _parse((await _dio.get('/api/users/me', options: basic)).data, RommUser.fromJson);
    } on DioException catch (e) {
      _fail(e);
    }
    if (expectedUserId != null && me.id != expectedUserId) {
      throw RommAuthException(RommAuthFailure.wrongUser, me.username);
    }
    if (!me.oauthScopes.contains('me.write')) {
      throw const RommAuthException(RommAuthFailure.insufficientScope, 'This RomM user may not create device tokens');
    }
    final scopes = [for (final s in gargosyScopes) if (me.oauthScopes.contains(s)) s];
    try {
      final r = await _dio.post('/api/client-tokens',
          data: {'name': tokenName, 'scopes': scopes, 'expires_in': null}, options: basic);
      return _parse<String>(r.data, (d) => d['raw_token'] as String);
    } on DioException catch (e) {
      _fail(e, on404: RommAuthFailure.serverTooOld);
    }
  }

  @override
  Future<RommUser> fetchMe(String token) async {
    try {
      return _parse<RommUser>((await _dio.get('/api/users/me', options: _bearer(token))).data, RommUser.fromJson);
    } on DioException catch (e) {
      _fail(e);
    }
  }

  @override
  Future<Uint8List?> fetchAvatar(String token, int userId) async {
    try {
      final r = await _dio.get<List<int>>('/api/users/$userId/avatar',
          options: _bearer(token).copyWith(responseType: ResponseType.bytes));
      final bytes = r.data;
      return bytes == null || bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } on DioException {
      return null;
    }
  }
}
