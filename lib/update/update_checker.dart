import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:pub_semver/pub_semver.dart';

import '../core/storage/app_preferences.dart';
import 'update_version.dart';

/// Where updates come from: releases only, or the rolling preview too.
enum UpdateChannel {
  latest('Latest'),
  preview('Preview');

  const UpdateChannel(this.label);
  final String label;

  static UpdateChannel fromName(String? name) => name == 'preview' ? preview : latest;
}

/// A release that can be installed: its `Gargosy-<version>.zip` and what
/// GitHub says about it.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.assetName,
    required this.assetUrl,
    required this.size,
    required this.htmlUrl,
    this.sha256,
    this.notes = '',
    this.prerelease = false,
  });

  final Version version;
  final String assetName;
  final String assetUrl;
  final int size;

  /// Lower-case hex SHA-256 of the zip, when GitHub gives one (`digest`).
  final String? sha256;

  /// The release body (Markdown).
  final String notes;
  final String htmlUrl;
  final bool prerelease;

  Map<String, Object?> toJson() => {
    'version': version.toString(),
    'assetName': assetName,
    'assetUrl': assetUrl,
    'size': size,
    'sha256': sha256,
    'notes': notes,
    'htmlUrl': htmlUrl,
    'prerelease': prerelease,
  };

  static ReleaseInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = UpdateVersion.parse('${json['version']}');
    final url = json['assetUrl'], name = json['assetName'], size = json['size'], html = json['htmlUrl'];
    if (version == null || url is! String || name is! String || size is! int || html is! String) return null;
    return ReleaseInfo(
      version: version,
      assetName: name,
      assetUrl: url,
      size: size,
      htmlUrl: html,
      sha256: json['sha256'] as String?,
      notes: json['notes'] as String? ?? '',
      prerelease: json['prerelease'] == true,
    );
  }
}

/// What a check found.
sealed class UpdateCheck {
  const UpdateCheck();
}

/// Nothing newer than the running version. [newest] is the newest version the
/// channel offers, when there is one: older than the running one after a
/// switch from Preview to Latest (never a downgrade).
class UpToDate extends UpdateCheck {
  const UpToDate({this.newest});
  final Version? newest;
}

class UpdateAvailable extends UpdateCheck {
  const UpdateAvailable(this.release);
  final ReleaseInfo release;
}

/// The check couldn't be made (offline, GitHub's limit, a preview being
/// rebuilt). Never an error dialog: the UI shows [reason] as a line.
class CheckFailed extends UpdateCheck {
  const CheckFailed(this.reason);
  final String reason;
}

/// App-wide update settings (`userdata\settings.json`, not per profile: the
/// app is shared).
class UpdatePrefs {
  UpdatePrefs._();
  static const channel = 'update.channel';
  static const autoCheck = 'update.autoCheck';
  static const lastCheck = 'update.lastCheck';
  static const etag = 'update.etag';

  /// The last answer, for a 304 and for a start within [UpdateChecker.minInterval].
  static const lastResult = 'update.lastResult';
}

/// Asks GitHub Releases of `GargIT/Gargosy` for a newer Gargosy (issue #16),
/// through the public API without a token. At most one request per call; a
/// call within [minInterval] of the last answer uses that answer instead,
/// unless forced (Check now). The saved ETag makes a repeat a 304, which
/// doesn't count against GitHub's 60 requests an hour.
class UpdateChecker {
  UpdateChecker({
    required this._dio,
    required this._prefs,
    required this.installed,
    DateTime Function()? clock,
    this.minInterval = const Duration(hours: 6),
  }) : _clock = clock ?? DateTime.now;

  static const repo = 'GargIT/Gargosy';
  static const apiBase = 'https://api.github.com/repos/$repo';
  static const releasesPage = 'https://github.com/$repo/releases';

  final Dio _dio;
  final AppPreferences _prefs;
  final DateTime Function() _clock;
  final Version installed;
  final Duration minInterval;

  UpdateChannel get channel => UpdateChannel.fromName(_prefs.getString(UpdatePrefs.channel));
  Future<void> setChannel(UpdateChannel c) => _prefs.setString(UpdatePrefs.channel, c.name);

  bool get autoCheck => _prefs.getBool(UpdatePrefs.autoCheck) ?? true;
  Future<void> setAutoCheck(bool on) => _prefs.setBool(UpdatePrefs.autoCheck, on);

  DateTime? get lastCheck => DateTime.tryParse(_prefs.getString(UpdatePrefs.lastCheck) ?? '');

  String _url(UpdateChannel c) =>
      c == UpdateChannel.latest ? '$apiBase/releases/latest' : '$apiBase/releases?per_page=10';

  /// Checks [channel]. Without [force], an answer younger than [minInterval]
  /// is used again without asking GitHub; null when there is none to use.
  Future<UpdateCheck?> check({bool force = false}) async {
    final c = channel;
    final url = _url(c);
    final cached = _cached(c);
    final last = lastCheck;
    if (!force && last != null && _clock().difference(last) < minInterval) {
      return cached == null ? null : _compare(cached.release);
    }

    final etag = _savedEtag(url);
    final Response<Object?> response;
    try {
      response = await _dio.get<Object?>(
        url,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            if (etag != null && cached != null) 'If-None-Match': etag,
          },
          validateStatus: (_) => true,
          followRedirects: true,
        ),
      );
    } on DioException catch (e) {
      return CheckFailed(_networkReason(e));
    }

    final status = response.statusCode ?? 0;
    if (status == 304 && cached != null) {
      await _stamp();
      return _compare(cached.release);
    }
    if (status == 404) {
      // No release yet, or the preview is being rebuilt (deleted, then made again).
      return const CheckFailed('GitHub has no release on this channel right now. Try again in a few minutes.');
    }
    if (status == 403 || status == 429) {
      return const CheckFailed("GitHub's limit for update checks was reached. Try again in an hour.");
    }
    if (status != 200) return CheckFailed('GitHub answered $status.');

    final ReleaseInfo? newest;
    try {
      final data = response.data;
      final body = data is String ? jsonDecode(data) : data;
      newest = c == UpdateChannel.latest ? _fromRelease(body, allowPrerelease: false) : _newestOf(body);
    } on FormatException {
      return const CheckFailed("GitHub's answer couldn't be read.");
    }

    final tag = response.headers.value('etag');
    if (tag != null) {
      await _prefs.setString(UpdatePrefs.etag, jsonEncode({'url': url, 'etag': tag}));
    } else {
      await _prefs.remove(UpdatePrefs.etag);
    }
    await _prefs.setString(UpdatePrefs.lastResult, jsonEncode({'channel': c.name, 'release': newest?.toJson()}));
    await _stamp();
    return _compare(newest);
  }

  UpdateCheck _compare(ReleaseInfo? newest) {
    if (newest != null && UpdateVersion.isNewer(newest.version, installed)) return UpdateAvailable(newest);
    return UpToDate(newest: newest?.version);
  }

  Future<void> _stamp() => _prefs.setString(UpdatePrefs.lastCheck, _clock().toUtc().toIso8601String());

  ({ReleaseInfo? release})? _cached(UpdateChannel c) {
    try {
      final json = jsonDecode(_prefs.getString(UpdatePrefs.lastResult) ?? '');
      if (json is! Map || json['channel'] != c.name) return null;
      return (release: ReleaseInfo.fromJson(json['release']));
    } on FormatException {
      return null;
    }
  }

  String? _savedEtag(String url) {
    try {
      final json = jsonDecode(_prefs.getString(UpdatePrefs.etag) ?? '');
      return json is Map && json['url'] == url ? json['etag'] as String? : null;
    } on FormatException {
      return null;
    }
  }

  /// The newest Gargosy among a page of releases, pre-release or not.
  static ReleaseInfo? _newestOf(Object? body) {
    if (body is! List) throw const FormatException('not a list of releases');
    ReleaseInfo? best;
    for (final r in body) {
      final info = _fromRelease(r, allowPrerelease: true);
      if (info != null && (best == null || info.version > best.version)) best = info;
    }
    return best;
  }

  /// [release]'s `Gargosy-<version>.zip`, or null when it has none (or is a
  /// draft, or a pre-release where they aren't wanted).
  static ReleaseInfo? _fromRelease(Object? release, {required bool allowPrerelease}) {
    if (release is! Map) throw const FormatException('not a release');
    if (release['draft'] == true) return null;
    final prerelease = release['prerelease'] == true;
    if (prerelease && !allowPrerelease) return null;
    final assets = release['assets'];
    if (assets is! List) return null;
    ReleaseInfo? best;
    for (final a in assets) {
      if (a is! Map) continue;
      final name = a['name'], url = a['browser_download_url'], size = a['size'];
      if (name is! String || url is! String || size is! int) continue;
      final version = UpdateVersion.fromAsset(name);
      if (version == null || (best != null && version <= best.version)) continue;
      final digest = a['digest'];
      best = ReleaseInfo(
        version: version,
        assetName: name,
        assetUrl: url,
        size: size,
        sha256: digest is String && digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
        notes: release['body'] as String? ?? '',
        htmlUrl: release['html_url'] as String? ?? releasesPage,
        prerelease: prerelease,
      );
    }
    return best;
  }

  static String _networkReason(DioException e) => switch (e.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout => "Couldn't reach GitHub. Check the connection.",
    _ => "Couldn't check: ${e.message ?? e.type.name}",
  };
}
