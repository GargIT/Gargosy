// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

enum ReleasePlatform {
  github,
  gitea,
  dolphin,
  // Gargosy: GitLab's releases API (Ryujinx's Ryubing, issue #9).
  gitlab,
}

class ReleaseService {
  final Dio _dio;
  final String? giteaBaseUrl;

  ReleaseService(this._dio, {this.giteaBaseUrl});

  /// Fetches available release assets from a repo (GitHub or Gitea).
  Future<List<Map<String, String>>> getLatestReleaseAssets({
    required ReleasePlatform platform,
    required String repo,
    List<String> requiredFilters = const [],
    List<String> excludedFilters = const [],
    String? baseUrl,
  }) async {
    try {
      String url;
      Map<String, String> headers;

      if (platform == ReleasePlatform.github) {
        url = 'https://api.github.com/repos/$repo/releases/latest';
        headers = {'Accept': 'application/vnd.github.v3+json'};
      } else if (platform == ReleasePlatform.dolphin) {
        // For Dolphin, we scrape the official download page
        return await _scrapeDolphin(requiredFilters, excludedFilters);
      } else if (platform == ReleasePlatform.gitlab) {
        return await _gitlab(baseUrl!, repo, requiredFilters, excludedFilters);
      } else {
        final base = baseUrl ?? giteaBaseUrl ?? 'https://git.eden-emu.dev';
        url = '$base/api/v1/repos/$repo/releases/latest';
        headers = {'Accept': 'application/json'};
      }

      try {
        final response = await _dio.get(url, options: Options(headers: headers));

        if (response.statusCode == 200) {
          return _parseApiAssets(response.data['assets'], requiredFilters, excludedFilters);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 403 || e.response?.statusCode == 429) {
          return await _scrapeFallback(platform, repo, requiredFilters, excludedFilters, baseUrl);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Gargosy: the newest stable release on a GitLab instance ([base], the
  /// project [repo] as `group/name`) with files matching the filters.
  /// GitLab lists releases newest first; an upcoming release, a canary or a
  /// pre-release tag (`-rc`, `-beta`) is skipped, never offered.
  Future<List<Map<String, String>>> _gitlab(
    String base,
    String repo,
    List<String> requiredFilters,
    List<String> excludedFilters,
  ) async {
    try {
      final response = await _dio.get<dynamic>(
        '$base/api/v4/projects/${Uri.encodeComponent(repo)}/releases?per_page=20',
        options: Options(headers: {'Accept': 'application/json', 'User-Agent': 'Gargosy'}),
      );
      final releases = response.data is List ? response.data as List : const [];
      return gitlabAssets(releases, requiredFilters, excludedFilters);
    } catch (e) {
      debugPrint('[Release] GitLab $repo: $e');
      return [];
    }
  }

  /// [releases] (GitLab's `/releases` JSON) → the first stable release's
  /// matching files.
  @visibleForTesting
  static List<Map<String, String>> gitlabAssets(
    List<dynamic> releases,
    List<String> requiredFilters,
    List<String> excludedFilters,
  ) {
    final unstable = RegExp(r'canary|nightly|-rc|beta|alpha|preview', caseSensitive: false);
    for (final release in releases.whereType<Map>()) {
      final tag = '${release['tag_name'] ?? ''} ${release['name'] ?? ''}';
      if (release['upcoming_release'] == true || unstable.hasMatch(tag)) continue;
      final links = (release['assets'] is Map ? release['assets']['links'] : null) as List? ?? const [];
      final out = <Map<String, String>>[];
      for (final link in links.whereType<Map>()) {
        final name = (link['name'] ?? '').toString();
        final url = (link['direct_asset_url'] ?? link['url'] ?? '').toString();
        if (name.isEmpty || !url.startsWith('https://')) continue;
        final lower = name.toLowerCase();
        if (requiredFilters.every((f) => lower.contains(f.toLowerCase())) &&
            !excludedFilters.any((f) => lower.contains(f.toLowerCase()))) {
          out.add({'name': name, 'url': url});
        }
      }
      if (out.isNotEmpty) return out;
    }
    return [];
  }

  List<Map<String, String>> _parseApiAssets(
    List<dynamic> assets,
    List<String> requiredFilters,
    List<String> excludedFilters,
  ) {
    List<Map<String, String>> matchingAssets = [];
    for (final asset in assets) {
      final name = (asset['name'] as String);
      final downloadUrl = asset['browser_download_url'] as String;

      final matchesRequired =
          requiredFilters.isEmpty || requiredFilters.every((f) => name.toLowerCase().contains(f.toLowerCase()));
      final matchesExcluded = excludedFilters.any((f) => name.toLowerCase().contains(f.toLowerCase()));

      if (matchesRequired && !matchesExcluded) {
        matchingAssets.add({'name': name, 'url': downloadUrl});
      }
    }
    return matchingAssets;
  }

  Future<List<Map<String, String>>> _scrapeFallback(
    ReleasePlatform platform,
    String repo,
    List<String> requiredFilters,
    List<String> excludedFilters,
    String? baseUrl,
  ) async {
    try {
      if (platform == ReleasePlatform.gitea) {
        // Gitea HTML scrape still works fine
        final base = baseUrl ?? giteaBaseUrl ?? 'https://git.eden-emu.dev';
        return await _htmlScrape('$base/$repo/releases/latest', base, requiredFilters, excludedFilters);
      }

      // GitHub (the API's hourly quota is used up): the website's
      // /releases/latest redirects to the latest release, as the API's
      // releases/latest would. Gargosy: the Atom feed listed pre-releases and
      // nightlies first, so a fallback picked those (or nothing, for xemu).
      final latest = await _dio.get<String>(
        'https://github.com/$repo/releases/latest',
        options: Options(
          headers: {'User-Agent': 'Gargosy'},
          followRedirects: false,
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final location = latest.headers.value('location') ?? '';
      final tagAt = location.indexOf('/releases/tag/');
      if (tagAt < 0) return [];
      final tag = location.substring(tagAt + '/releases/tag/'.length);

      // The release's files, as its page lists them.
      final pageResponse = await _dio.get<String>(
        'https://github.com/$repo/releases/expanded_assets/$tag',
        options: Options(headers: {'User-Agent': 'Gargosy'}, responseType: ResponseType.plain),
      );
      if ((pageResponse.statusCode ?? 0) < 200 || (pageResponse.statusCode ?? 0) >= 300) return [];

      return _parseHtmlAssets(pageResponse.data ?? '', 'https://github.com', requiredFilters, excludedFilters);
    } catch (e) {
      debugPrint('[Release] fallback for $repo failed: $e');
      return [];
    }
  }

  Future<List<Map<String, String>>> _htmlScrape(
    String url,
    String base,
    List<String> requiredFilters,
    List<String> excludedFilters,
  ) async {
    final response = await http.get(Uri.parse(url), headers: {'User-Agent': 'Gargosy'});
    if (response.statusCode < 200 || response.statusCode >= 300) return [];
    return _parseHtmlAssets(response.body, base, requiredFilters, excludedFilters);
  }

  List<Map<String, String>> _parseHtmlAssets(
    String html,
    String base,
    List<String> requiredFilters,
    List<String> excludedFilters,
  ) {
    final regex = RegExp(r'href="([^"]+/releases/download/[^"]+)"');
    final matches = regex.allMatches(html);
    final List<Map<String, String>> matchingAssets = [];

    for (final match in matches) {
      final path = match.group(1)!;
      final fullUrl = path.startsWith('http') ? path : '$base$path';
      final name = fullUrl.split('/').last;

      final matchesRequired =
          requiredFilters.isEmpty || requiredFilters.every((f) => name.toLowerCase().contains(f.toLowerCase()));
      final matchesExcluded = excludedFilters.any((f) => name.toLowerCase().contains(f.toLowerCase()));

      if (matchesRequired && !matchesExcluded) {
        matchingAssets.add({'name': name, 'url': fullUrl});
      }
    }
    return matchingAssets;
  }

  /// The newest Dolphin release's files that match the filters, from the
  /// update API Dolphin's own updater reads (`/update/latest/beta` is its
  /// release channel). Gargosy: the download page is behind a bot check that
  /// answers programs with a 403 page, so it isn't scraped any more.
  Future<List<Map<String, String>>> _scrapeDolphin(List<String> requiredFilters, List<String> excludedFilters) async {
    try {
      final response = await _dio.get<dynamic>(
        'https://dolphin-emu.org/update/latest/beta',
        options: Options(headers: {'User-Agent': 'Gargosy'}),
      );
      final artifacts = response.data is Map ? (response.data['artifacts'] as List? ?? const []) : const [];
      final List<Map<String, String>> matchingAssets = [];
      for (final artifact in artifacts.whereType<Map>()) {
        final fullUrl = artifact['url']?.toString() ?? '';
        if (!fullUrl.startsWith('https://dl.dolphin-emu.org/')) continue;
        final name = fullUrl.split('/').last;

        final matchesRequired =
            requiredFilters.isEmpty || requiredFilters.every((f) => name.toLowerCase().contains(f.toLowerCase()));
        final matchesExcluded = excludedFilters.any((f) => name.toLowerCase().contains(f.toLowerCase()));
        if (matchesRequired && !matchesExcluded && !matchingAssets.any((a) => a['url'] == fullUrl)) {
          matchingAssets.add({'name': name, 'url': fullUrl});
        }
      }
      return matchingAssets;
    } catch (e) {
      debugPrint('[Dolphin] update API error: $e');
      return [];
    }
  }
}
