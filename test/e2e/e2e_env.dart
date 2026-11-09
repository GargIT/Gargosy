import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:gargosy/core/romm/romm_auth_client.dart';
import 'package:gargosy/core/romm/romm_config.dart';
import 'package:gargosy/core/romm/romm_service.dart';

/// Where the end-to-end tests (#242) run: a RomM named by `ROMM_E2E_*`
/// (`docs/e2e-tests.md`). Without `ROMM_E2E_URL` they're skipped.
class E2eEnv {
  E2eEnv._(this.url, this.user, this.password, this.token, this.adminUser, this.adminPassword, this.platform);

  static E2eEnv? read() {
    final env = io.Platform.environment;
    final url = env['ROMM_E2E_URL'] ?? '';
    if (url.isEmpty) return null;
    String? opt(String k) => (env[k] ?? '').isEmpty ? null : env[k];
    return E2eEnv._(
      url,
      opt('ROMM_E2E_USER'),
      opt('ROMM_E2E_PASSWORD'),
      opt('ROMM_E2E_TOKEN'),
      opt('ROMM_E2E_ADMIN_USER'),
      opt('ROMM_E2E_ADMIN_PASSWORD'),
      opt('ROMM_E2E_PLATFORM') ?? 'gb',
    );
  }

  /// Why the tests are skipped, or null when they run.
  static final String? skip = read() == null ? 'Set ROMM_E2E_URL to run (docs/e2e-tests.md)' : null;

  final String url;
  final String? user;
  final String? password;

  /// A client token of the test user, made in RomM, instead of a password.
  final String? token;
  final String? adminUser;
  final String? adminPassword;

  /// The slug of the platform with the test games.
  final String platform;

  bool get hasAdmin => adminUser != null && adminPassword != null;

  /// The test user's login: [token] when given, else one made from the password.
  Future<E2eLogin> signIn() async {
    if (token case final t?) return E2eLogin.withToken(url, t);
    if (user == null || password == null) {
      throw StateError('Set ROMM_E2E_TOKEN, or ROMM_E2E_USER and ROMM_E2E_PASSWORD');
    }
    return E2eLogin.signIn(url, user!, password!);
  }

  /// What every name the tests make on RomM starts with, so a run left half
  /// way can be found and cleaned up by hand.
  static const mark = 'Gargosy E2E';
}

/// A RomM login as Gargosy has one: a client token. [close] deletes a token
/// the tests made.
class E2eLogin {
  E2eLogin._(this.token, this.tokenName, this.romm, this._url, this._auth);

  /// A client token made from the password, as a profile's password sign-in does.
  static Future<E2eLogin> signIn(String url, String user, String password) async {
    final name = '${E2eEnv.mark} ${DateTime.now().toUtc().toIso8601String()}';
    final token = await RommAuthClient(url).loginWithPassword(username: user, password: password, tokenName: name);
    return E2eLogin._(token, name, _service(url, token), url, 'Basic ${base64Encode(utf8.encode('$user:$password'))}');
  }

  /// A client token made in RomM; it stays when the tests end.
  static E2eLogin withToken(String url, String token) =>
      E2eLogin._(token, null, _service(url, token), url, 'Bearer $token');

  static RommService _service(String url, String token) =>
      RommService(RomMConfig(baseUrl: url, username: '', password: '', apiKey: token), skipConnectivityCheck: true);

  final String token;

  /// The token's name when the tests made it.
  final String? tokenName;
  final RommService romm;
  final String _url;
  final String _auth;

  /// RomM as the test user, for the tests' own cleanup (not Gargosy's calls,
  /// which go through [romm]).
  late final Dio raw = Dio(
    BaseOptions(baseUrl: RommAuthClient.normalizeBaseUrl(_url), headers: {'Authorization': _auth}),
  );

  /// Deletes the client token the tests made.
  Future<void> close() async {
    if (tokenName == null) return;
    final tokens = (await raw.get<List<dynamic>>('/api/client-tokens')).data ?? const [];
    for (final t in tokens) {
      if (t is Map && t['name'] == tokenName) await raw.delete<void>('/api/client-tokens/${t['id']}');
    }
  }
}
