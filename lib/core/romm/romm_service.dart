// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';
import '../platform/platform_info.dart';
import 'romm_models.dart';
import 'romm_state.dart';

part 'romm_service/library.dart';
part 'romm_service/users.dart';
part 'romm_service/saves.dart';
part 'romm_service/states.dart';
part 'romm_service/sharing.dart';
part 'romm_service/play.dart';
part 'romm_service/firmware.dart';

/// Gargosy: what deleting a game on RomM came to. [notAllowed]: RomM
/// refused (the user may not delete, or the profile's sign-in predates Gargosy
/// asking for `roms.write`).
enum RomDeleteResult { deleted, notAllowed, failed }

String _normalizeBaseUrl(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

/// What every part of [RommService] reaches: the server, its client and auth.
abstract class _RommBase {
  RomMConfig get _config;
  Dio get _dio;
  Options get _authOptions;
}

/// Gargosy: every RomM call. The calls live in `romm_service/`, one part per
/// area, each a mixin on [_RommBase]; this file keeps the client, its auth
/// and connectivity, capabilities and device registration.
class RommService extends _RommBase
    with _RommLibrary, _RommUsers, _RommSaves, _RommStates, _RommSharing, _RommPlay, _RommFirmware
    implements RommStatesApi {
  @override
  RomMConfig _config;
  @override
  final Dio _dio;
  @override
  Options _authOptions;
  final ValueNotifier<bool> isOffline = ValueNotifier(false);
  Timer? _heartbeatTimer;
  final PlatformInfo _platform;

  RomMConfig get config => _config;

  /// For the library API (romm_library_api.dart), which shares this client and its auth.
  Dio get dio => _dio;
  Options get authOptions => _authOptions;

  static String get _ua => 'Gargosy/${AppConstants.version}';

  void updateConfig(RomMConfig newConfig) {
    _config = newConfig;
    _dio.options.baseUrl = _normalizeBaseUrl(newConfig.baseUrl);
    _authOptions = _computeAuthOptions(newConfig);
  }

  /// True only for the connectivity/capabilities poll (`GET /api/heartbeat`)
  /// — NOT `/api/activity/heartbeat` (issue #93), which merely contains the
  /// same substring. Used to quiet debug logging and skip retries for the
  /// former without also silencing the latter.
  static bool _isConnectivityHeartbeat(String path) => path == '/api/heartbeat';

  RommService(this._config, {Dio? dio, PlatformInfo? platform, bool skipConnectivityCheck = false})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _normalizeBaseUrl(_config.baseUrl),
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'User-Agent': _ua, 'Accept': 'application/json'},
            ),
          ),
      _authOptions = _computeAuthOptions(_config),
      _platform = platform ?? PlatformInfo.current {
    if (dio != null) {
      _dio.options.baseUrl = _normalizeBaseUrl(_config.baseUrl);
    }

    if (_config.trustSelfSigned) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = io.HttpClient()..badCertificateCallback = (cert, host, port) => true;
          return client;
        },
      );
    }

    if (kDebugMode || _platform.isLinux || _platform.isMacOS) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (!_isConnectivityHeartbeat(options.path) && !options.path.contains('/api/roms')) {
              debugPrint('[RomM-Network] -> ${options.method} ${options.uri}');
            }
            return handler.next(options);
          },
          onResponse: (response, handler) {
            final path = response.requestOptions.path;
            if (!_isConnectivityHeartbeat(path) && !path.contains('/api/roms')) {
              debugPrint('[RomM-Network] <- ${response.statusCode} ${response.requestOptions.uri}');
            } else if (path.contains('/api/roms')) {
              final offset = response.requestOptions.queryParameters['offset'] ?? 0;
              final limit = response.requestOptions.queryParameters['limit'] ?? 'all';
              debugPrint('[RomM-Network] ~ Fetched games batch (offset: $offset, limit: $limit)');
            }
            return handler.next(response);
          },
          onError: (e, handler) {
            if (!_isConnectivityHeartbeat(e.requestOptions.path)) {
              debugPrint('[RomM-Network] ! ERROR ${e.requestOptions.uri}: ${e.message}');
            }
            return handler.next(e);
          },
        ),
      );
    }

    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException e, ErrorInterceptorHandler handler) async {
          // Retry logic for transient network errors (especially on Steam Deck wake-up)
          final path = e.requestOptions.path;
          final isRetryable =
              e.type != DioExceptionType.cancel &&
              e.type != DioExceptionType.badResponse &&
              e.requestOptions.extra['no_retry'] != true &&
              !_isConnectivityHeartbeat(path);

          if (isRetryable && e.requestOptions.extra['retry_count'] == null) {
            e.requestOptions.extra['retry_count'] = 0;
          }

          final retryCount = e.requestOptions.extra['retry_count'] as int? ?? 0;

          if (isRetryable && retryCount < 2) {
            e.requestOptions.extra['retry_count'] = retryCount + 1;
            debugPrint('[RomM-Network] ! Retrying ${e.requestOptions.uri} (Attempt ${retryCount + 1})...');
            await Future.delayed(Duration(seconds: 1 * (retryCount + 1)));
            try {
              final response = await _dio.fetch(e.requestOptions);
              return handler.resolve(response);
            } catch (retryError) {
              return handler.next(retryError is DioException ? retryError : e);
            }
          }
          return handler.next(e);
        },
      ),
    );

    if (!skipConnectivityCheck) {
      _initializeConnectivity();
    }
  }

  void startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        await _dio.get(
          '/api/heartbeat',
          options: Options(
            headers: {'Authorization': _authOptions.headers?['Authorization']},
            sendTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 3),
          ),
        );
        if (isOffline.value) {
          isOffline.value = false;
        }
      } catch (e) {
        if (!isOffline.value) {
          isOffline.value = true;
        }
      }
    });
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
  }

  Future<void> _initializeConnectivity() async {
    try {
      final uri = Uri.parse(_config.baseUrl);
      final socket = await io.Socket.connect(
        uri.host,
        uri.port == 0 ? (uri.scheme == 'https' ? 443 : 80) : uri.port,
        timeout: const Duration(seconds: 2),
      );
      await socket.close();

      await getPlatforms();
      isOffline.value = false;
    } catch (e) {
      debugPrint('[RommService] Server unreachable, switching to offline mode.');
      isOffline.value = true;
    }
  }

  static Options _computeAuthOptions(RomMConfig config) {
    final headers = <String, dynamic>{};

    if (config.apiKey.isNotEmpty) {
      // Send both headers for maximum compatibility across all RomM versions and proxies.
      // Standard API Keys often work via X-Api-Key, while Client Tokens often require Bearer.
      // Many setups use the API Key in the Bearer field, so we provide both to be safe.
      headers['Authorization'] = 'Bearer ${config.apiKey}';
      headers['X-Api-Key'] = config.apiKey;
    } else if (config.token != null && config.token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.token}';
    } else if (config.username.isNotEmpty && config.password.isNotEmpty) {
      final basic = 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
      headers['Authorization'] = basic;
    }

    return Options(headers: headers);
  }

  static Future<String> exchangePairingCode(String baseUrl, String code, {bool trustSelfSigned = false}) async {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    final dio = Dio(
      BaseOptions(
        baseUrl: normalizedUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'User-Agent': _ua},
      ),
    );

    if (trustSelfSigned) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = io.HttpClient()..badCertificateCallback = (cert, host, port) => true;
          return client;
        },
      );
    }

    const maxRetries = 2;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await dio.post('/api/client-tokens/exchange', data: {'code': code});

        final token = response.data['raw_token'] as String?;
        if (token == null || token.isEmpty) throw Exception('Pairing failed: no token in response');

        return token;
      } on DioException catch (e) {
        if (attempt < maxRetries && e.type != DioExceptionType.badResponse) {
          await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }

    throw Exception('Pairing failed after $maxRetries retries');
  }

  // ---------------------------------------------------------------------------
  // Capabilities / version detection
  // ---------------------------------------------------------------------------

  /// Fetches [RommCapabilities] from /api/heartbeat once and caches the result.
  RommCapabilities _capabilities = RommCapabilities.unknown();
  bool _capabilitiesFetched = false;

  RommCapabilities get capabilities => _capabilities;

  Future<RommCapabilities> fetchCapabilities() async {
    if (_capabilitiesFetched) return _capabilities;
    try {
      final response = await _dio.get(
        '/api/heartbeat',
        options: Options(
          headers: {'Authorization': _authOptions.headers?['Authorization']},
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      if (response.statusCode == 200) {
        final version = (response.data?['SYSTEM']?['VERSION'] as String?) ?? '0.0.0';
        final raEnabled = response.data?['METADATA_SOURCES']?['RA_API_ENABLED'];
        _capabilities = RommCapabilities(
          version: version,
          retroAchievementsEnabled: raEnabled is bool ? raEnabled : null,
        );
        debugPrint('[RomM] Detected version: $version → $_capabilities');
        // Gargosy: kept only when RomM answered. A profile opened while RomM
        // was down asks again, instead of syncing the legacy way for good.
        _capabilitiesFetched = true;
      }
    } catch (e) {
      debugPrint('[RomM] fetchCapabilities failed, defaulting to legacy for now: $e');
    }
    return _capabilities;
  }

  // ---------------------------------------------------------------------------
  // Device registration (RomM 4.9+)
  // ---------------------------------------------------------------------------

  /// Registers this Gargosy install as a device and returns the persistent UUID.
  /// [allowExisting] = true recovers an existing registration on re-install.
  Future<String?> registerDevice({
    required String name,
    required String platform,
    String? hostname,
    String? clientVersion,
    bool allowExisting = true,
  }) async {
    try {
      final body = {
        'name': name,
        'platform': platform,
        'client': 'Gargosy',
        'client_version': clientVersion ?? AppConstants.version,
        'hostname': ?hostname,
      };
      final response = await _dio.post(
        '/api/devices',
        queryParameters: allowExisting ? {'allow_existing': 'true'} : null,
        data: body,
        options: _authOptions.copyWith(contentType: 'application/json'),
      );
      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
        final deviceId = response.data['device_id']?.toString() ?? response.data['id']?.toString();
        debugPrint('[RomM] Registered device: $deviceId');
        return deviceId;
      }
    } catch (e) {
      debugPrint('[RomM] registerDevice error: $e');
    }
    return null;
  }

  String get authHeader {
    if (_config.apiKey.isNotEmpty) return 'Bearer ${_config.apiKey}';
    if (_config.token != null && _config.token!.isNotEmpty) return 'Bearer ${_config.token}';
    return 'Basic ${base64Encode(utf8.encode('${_config.username}:${_config.password}'))}';
  }

  /// How long a state download may go without receiving data before it fails.
  /// Dio's receive timeout is the longest gap between data events, not a limit
  /// on the whole transfer, so a slow download that keeps progressing still
  /// finishes. Downloads run before launch (awaited), so a stalled server must
  /// not hold them for the 5 minutes uploads are allowed.
  static const Duration stateDownloadInactivityTimeout = Duration(seconds: 30);
}
