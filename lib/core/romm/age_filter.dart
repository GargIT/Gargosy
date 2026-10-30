import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../profiles/age_limit.dart';
import 'romm_library_api.dart';
import 'romm_models.dart';
import 'romm_service.dart';

/// #224: every games list asked of RomM (`GET /api/roms`: galleries,
/// Search, collections, Home's rows, Random) leaves out the games rated
/// above the profile's [limit], by RomM's own `age_ratings` filter with
/// `age_ratings_logic=none`: a game with any rating above it is out, so
/// paging, counts and the A–Z rail stay RomM's. Unrated games (Hide unrated)
/// are left out where the games are shown. The library's ratings are RomM's
/// `filter_values.age_ratings`, read again after [refresh]. When they can't
/// be read, the list fails rather than come unfiltered.
class AgeFilterInterceptor extends Interceptor {
  AgeFilterInterceptor(this.limit, this._readRatings, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final AgeLimit limit;
  final Future<List<String>> Function() _readRatings;
  final DateTime Function() _now;
  Future<List<String>>? _ratings;
  DateTime? _readAt;

  /// How long the library's ratings are kept: a game scanned since may bring
  /// a new one.
  static const refresh = Duration(minutes: 5);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!limit.isOn || options.method != 'GET' || options.path != '/api/roms') return handler.next(options);
    try {
      final at = _readAt;
      if (_ratings == null || at == null || _now().difference(at) > refresh) {
        _readAt = _now();
        _ratings = _readRatings();
      }
      final above = limit.ratingsAbove(await _ratings!);
      if (above.isNotEmpty) {
        options.queryParameters = {...options.queryParameters, 'age_ratings': above, 'age_ratings_logic': 'none'};
      }
      handler.next(options);
    } on Object catch (e) {
      _ratings = null;
      debugPrint("[Age] RomM's ratings not read, the list is refused: $e");
      handler.reject(DioException(requestOptions: options, error: e, message: 'age ratings not read'));
    }
  }
}

/// [inner] for a profile with an age [limit]: what RomM picks without the
/// `/api/roms` filter (For you, Similar games, On this day's check) is
/// checked game by game, and a Random that lands above the limit (or on an
/// unrated game with Hide unrated) draws again, a few times. Gallery pages
/// stay RomM's raw pages: `GalleryView` hides what it must, keeping RomM's
/// positions for paging and the A–Z rail.
class AgeLimitedLibraryApi implements LibraryApi {
  AgeLimitedLibraryApi(this.inner, this.limit);

  final LibraryApi inner;
  final AgeLimit limit;

  @override
  Future<GalleryPage> page(
    GalleryQuery q, {
    int offset = 0,
    int limit = RommLibraryApi.pageSize,
    bool withFilterValues = false,
    bool withCharIndex = false,
    bool foldVersions = false,
  }) => inner.page(
    q,
    offset: offset,
    limit: limit,
    withFilterValues: withFilterValues,
    withCharIndex: withCharIndex,
    foldVersions: foldVersions,
  );

  @override
  Future<List<RommCollection>> collections() => inner.collections();

  @override
  Future<List<RommCollection>> smartCollections() => inner.smartCollections();

  @override
  Future<List<RommCollection>> virtualCollections(String type) => inner.virtualCollections(type);

  @override
  Future<RommCollection> setFavourite(String gameId, bool favourite, {required int userId}) =>
      inner.setFavourite(gameId, favourite, userId: userId);

  @override
  Future<Game?> randomGame({int? platformId, GalleryQuery? within}) async {
    for (var i = 0; i < 3; i++) {
      final g = await inner.randomGame(platformId: platformId, within: within);
      if (g == null || limit.allows(g)) return g;
    }
    return null;
  }

  @override
  Future<List<Game>> recommended({int limit = 20}) async =>
      (await inner.recommended(limit: limit)).where(this.limit.allows).toList();

  @override
  Future<List<Game>> similar(String gameId, {int limit = 12}) async =>
      (await inner.similar(gameId, limit: limit)).where(this.limit.allows).toList();

  @override
  Future<GalleryPage> releasedOn(DateTime today, {int limit = 20}) async {
    final page = await inner.releasedOn(today, limit: limit);
    return GalleryPage(games: page.games.where(this.limit.allows).toList(), total: page.total);
  }

  @override
  Future<List<RomNote>> notes(String gameId) => inner.notes(gameId);

  @override
  Future<void> addNote(String gameId, String title, String content) => inner.addNote(gameId, title, content);

  @override
  Future<void> deleteNote(String gameId, int noteId) => inner.deleteNote(gameId, noteId);
}

/// The library API of [romm] for a profile with [limit]: with a limit, on
/// its own copy of RomM's Dio with [AgeFilterInterceptor] (RommService's
/// own calls, the ratings read among them, stay unfiltered), wrapped in
/// [AgeLimitedLibraryApi]. [dio] replaces RomM's in tests.
LibraryApi libraryApiFor(RommService romm, AgeLimit limit, {Dio? dio}) {
  final base = dio ?? romm.dio;
  if (!limit.isOn) return RommLibraryApi(base, () => romm.authOptions);
  final filtered = Dio(base.options)
    ..httpClientAdapter = base.httpClientAdapter
    ..transformer = base.transformer;
  filtered.interceptors
    // Dio's own content-type step comes twice; it only fills in what's missing.
    ..addAll(base.interceptors)
    ..add(AgeFilterInterceptor(limit, romm.getLibraryAgeRatings));
  return AgeLimitedLibraryApi(RommLibraryApi(filtered, () => romm.authOptions), limit);
}
