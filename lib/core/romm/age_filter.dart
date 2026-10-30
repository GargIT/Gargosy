import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../profiles/age_limit.dart';
import 'romm_library_api.dart';
import 'romm_models.dart';

/// #224: every games list asked of RomM (`GET /api/roms`: galleries,
/// Search, collections, Home's rows, Random) leaves out what the profile's
/// [limit] hides, by RomM's own `age_ratings` filter, so paging, counts and
/// the A–Z rail stay RomM's. Games above the limit go with
/// `age_ratings_logic=none` (unrated ones stay); with Hide unrated, only the
/// allowed ratings go, with `any`. The library's ratings are RomM's
/// `filter_values.age_ratings`, read once.
class AgeFilterInterceptor extends Interceptor {
  AgeFilterInterceptor(this.limit, this._readRatings);

  final AgeLimit limit;
  final Future<List<String>> Function() _readRatings;
  Future<List<String>>? _ratings;

  /// Marks the request that reads the ratings, which isn't filtered.
  static const unfiltered = 'gargosy-unfiltered';

  /// What a request matching no rating at all sends (Hide unrated with
  /// nothing allowed): no game has it.
  static const noRating = '-';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!limit.isOn || options.method != 'GET' || options.path != '/api/roms' || options.extra[unfiltered] == true) {
      return handler.next(options);
    }
    try {
      final values = await (_ratings ??= _readRatings());
      final params = Map<String, dynamic>.of(options.queryParameters);
      if (limit.hideUnrated) {
        final allowed = limit.ratingsAllowed(values);
        params['age_ratings'] = allowed.isEmpty ? [noRating] : allowed;
        params['age_ratings_logic'] = 'any';
      } else {
        final above = limit.ratingsAbove(values);
        if (above.isNotEmpty) {
          params['age_ratings'] = above;
          params['age_ratings_logic'] = 'none';
        }
      }
      options.queryParameters = params;
    } on Object catch (e) {
      // Without the ratings, the lists are checked game by game instead.
      _ratings = null;
      debugPrint('[Age] RomM\'s ratings not read: $e');
    }
    handler.next(options);
  }
}

/// RomM's ratings across the library (`filter_values.age_ratings`), asked
/// with [dio] in one small request.
Future<List<String>> readLibraryRatings(Dio dio, Options options) async {
  final r = await dio.get<Object?>(
    '/api/roms',
    queryParameters: {'limit': 1, 'with_filter_values': true},
    options: options.copyWith(extra: {...?options.extra, AgeFilterInterceptor.unfiltered: true}),
  );
  final data = r.data;
  final values = data is Map && data['filter_values'] is Map ? (data['filter_values'] as Map)['age_ratings'] : null;
  return [
    for (final v in values is List ? values : const [])
      if (v is String && v.trim().isNotEmpty) v,
  ];
}

/// [inner] for a profile with an age [limit]: what RomM picks without the
/// `/api/roms` filter (For you, Similar games) is checked game by game, and
/// a Random that lands above the limit (an older RomM without the filter)
/// draws again, a few times.
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
    for (var i = 0; i < 5; i++) {
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
  Future<GalleryPage> releasedOn(DateTime today, {int limit = 20}) => inner.releasedOn(today, limit: limit);

  @override
  Future<List<RomNote>> notes(String gameId) => inner.notes(gameId);

  @override
  Future<void> addNote(String gameId, String title, String content) => inner.addNote(gameId, title, content);

  @override
  Future<void> deleteNote(String gameId, int noteId) => inner.deleteNote(gameId, noteId);
}

/// [base] with the age filter for [limit] (a copy: RommService's own calls
/// stay unfiltered); [base] itself when there is no limit.
Dio ageFilteredDio(Dio base, AgeLimit limit, Options Function() auth) {
  if (!limit.isOn) return base;
  final dio = Dio(base.options)
    ..httpClientAdapter = base.httpClientAdapter
    ..transformer = base.transformer;
  dio.interceptors
    // Dio's own content-type step comes twice; it only fills in what's missing.
    ..addAll(base.interceptors)
    ..add(AgeFilterInterceptor(limit, () => readLibraryRatings(dio, auth())));
  return dio;
}
