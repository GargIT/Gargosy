import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'romm_models.dart';

/// Where a sort's order comes from: RomM's fields, the player's own, or
/// Gargosy's (only with On this PC on).
enum SortGroup {
  romm('ROMM'),
  yours('YOURS'),
  thisPc('THIS PC');

  const SortGroup(this.label);
  final String label;
}

/// Gallery sort orders, as RomM's `/api/roms` `order_by` names them (a
/// `Rom`, `RomUser` or metadata column, checked against RomM 5.4.0's
/// `_resolve_gallery_sort_key`; an older RomM sorts an unknown name by name).
enum GallerySort {
  name('name', 'Name', false),
  recentlyAdded('created_at', 'Recently added', true),
  lastPlayed('last_played', 'Last played', true),
  releaseDate('first_release_date', 'Release date', true),
  rating('average_rating', 'Rating', true),
  size('fs_size_bytes', 'Size', true),
  players('player_count', 'Players', true),
  length('hltb_main_story', 'Length', false),
  myRating('rating', 'My rating', true, SortGroup.yours),
  completion('completion', 'Completion', true, SortGroup.yours),
  status('status', 'Status', false, SortGroup.yours),

  /// Newest download first; Gargosy sorts it itself.
  downloaded('name', 'Downloaded', true, SortGroup.thisPc);

  const GallerySort(this.field, this.label, this.descByDefault, [this.group = SortGroup.romm]);
  final String field;
  final String label;
  final bool descByDefault;
  final SortGroup group;
}

const _keep = Object();

/// What a gallery shows: its scope (a platform, a collection, favourites or a
/// search), its sort and its filters.
@immutable
class GalleryQuery {
  const GalleryQuery({
    this.platformId,
    this.collectionId,
    this.favourites = false,
    this.search,
    this.sort = GallerySort.name,
    this.descending = false,
    this.genres = const {},
    this.regions = const {},
    this.lastPlayedOnly = false,
  });

  final int? platformId;
  final int? collectionId;
  final bool favourites;
  final String? search;
  final GallerySort sort;
  final bool descending;
  final Set<String> genres;
  final Set<String> regions;

  /// Only games the user has played (Home's "Continue playing").
  final bool lastPlayedOnly;

  GalleryQuery copyWith({
    Object? search = _keep,
    GallerySort? sort,
    bool? descending,
    Set<String>? genres,
    Set<String>? regions,
  }) => GalleryQuery(
    platformId: platformId,
    collectionId: collectionId,
    favourites: favourites,
    search: identical(search, _keep) ? this.search : search as String?,
    sort: sort ?? this.sort,
    descending: descending ?? this.descending,
    genres: genres ?? this.genres,
    regions: regions ?? this.regions,
    lastPlayedOnly: lastPlayedOnly,
  );

  bool get hasFilters => genres.isNotEmpty || regions.isNotEmpty;

  Map<String, dynamic> toParams({required int offset, required int limit, bool withFilterValues = false}) {
    final term = search?.trim() ?? '';
    return {
      'offset': offset,
      'limit': limit,
      'order_by': sort.field,
      'order_dir': descending ? 'desc' : 'asc',
      'with_char_index': false,
      // RomM builds the ordered id list of the whole result set unless told
      // not to; Gargosy never uses it.
      'with_rom_id_index': false,
      'with_filter_values': withFilterValues,
      if (lastPlayedOnly) 'last_played': true,
      if (platformId != null) 'platform_ids': [platformId],
      if (collectionId != null) 'collection_id': collectionId,
      if (favourites) 'favorite': true,
      if (term.isNotEmpty) 'search_term': term,
      if (genres.isNotEmpty) 'genres': (genres.toList()..sort()),
      if (regions.isNotEmpty) 'regions': (regions.toList()..sort()),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is GalleryQuery &&
      other.platformId == platformId &&
      other.collectionId == collectionId &&
      other.favourites == favourites &&
      other.search == search &&
      other.sort == sort &&
      other.descending == descending &&
      setEquals(other.genres, genres) &&
      setEquals(other.regions, regions) &&
      other.lastPlayedOnly == lastPlayedOnly;

  @override
  int get hashCode => Object.hash(
    platformId,
    collectionId,
    favourites,
    search,
    sort,
    descending,
    Object.hashAllUnordered(genres),
    Object.hashAllUnordered(regions),
    lastPlayedOnly,
  );
}

/// The values a gallery's filters can take (RomM's `filter_values`).
class FilterValues {
  const FilterValues({this.genres = const [], this.regions = const []});
  final List<String> genres;
  final List<String> regions;

  static List<String> _list(Object? v) => [
    for (final s in (v is List ? v : const []))
      if (s is String && s.isNotEmpty) s,
  ]..sort();

  factory FilterValues.fromJson(Map<String, dynamic> json) =>
      FilterValues(genres: _list(json['genres']), regions: _list(json['regions']));
}

class GalleryPage {
  const GalleryPage({required this.games, required this.total, this.filters});
  final List<Game> games;
  final int total;
  final FilterValues? filters;
}

class RommCollection {
  const RommCollection({
    required this.id,
    required this.name,
    this.description = '',
    this.romIds = const {},
    this.romCount = 0,
    this.coverPath,
    this.isFavorite = false,
    this.isPublic = false,
    this.userId,
    this.ownerUsername,
  });

  final int id;
  final String name;
  final String description;
  final Set<int> romIds;
  final int romCount;
  final String? coverPath;
  final bool isFavorite;
  final bool isPublic;
  final int? userId;
  final String? ownerUsername;

  factory RommCollection.fromJson(Map<String, dynamic> json) {
    final ids = {
      for (final i in (json['rom_ids'] is List ? json['rom_ids'] as List : const []))
        if (i is int) i,
    };
    return RommCollection(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      romIds: ids,
      romCount: json['rom_count'] is int ? json['rom_count'] as int : ids.length,
      coverPath: (json['path_cover_large'] ?? json['path_cover_small']) as String?,
      isFavorite: json['is_favorite'] == true,
      isPublic: json['is_public'] == true,
      userId: json['user_id'] as int?,
      ownerUsername: json['owner_username'] as String?,
    );
  }
}

/// What the library pages need from RomM. [RommLibraryApi] is the real one.
abstract class LibraryApi {
  Future<GalleryPage> page(
    GalleryQuery q, {
    int offset = 0,
    int limit = RommLibraryApi.pageSize,
    bool withFilterValues = false,
  });
  Future<List<RommCollection>> collections();

  /// Adds [gameId] to (or removes it from) the user's own favourites, creating
  /// that collection first when the user has none.
  Future<RommCollection> setFavourite(String gameId, bool favourite, {required int userId});

  /// A random game of the library (of one platform with [platformId]), or
  /// null when there is none.
  Future<Game?> randomGame({int? platformId});

  /// The user's notes on a game. Unlike the copied RommService calls, these
  /// throw when RomM can't be reached, so pages can show the error.
  Future<List<RomNote>> notes(String gameId);

  /// Adds a private note.
  Future<void> addNote(String gameId, String title, String content);
  Future<void> deleteNote(String gameId, int noteId);
}

class RommLibraryApi implements LibraryApi {
  RommLibraryApi(this.dio, this.auth);

  final Dio dio;
  final Options Function() auth;

  static const pageSize = 48;

  @override
  Future<GalleryPage> page(
    GalleryQuery q, {
    int offset = 0,
    int limit = pageSize,
    bool withFilterValues = false,
  }) async {
    final r = await dio.get(
      '/api/roms',
      queryParameters: q.toParams(offset: offset, limit: limit, withFilterValues: withFilterValues),
      options: auth(),
    );
    final data = r.data as Map<String, dynamic>;
    final games = [
      for (final g in (data['items'] as List? ?? const []))
        if (g is Map<String, dynamic>) Game.fromJson(g),
    ];
    final total = data['total'] is int ? data['total'] as int : offset + games.length;
    final fv = data['filter_values'];
    return GalleryPage(
      games: games,
      total: total,
      filters: withFilterValues && fv is Map<String, dynamic> ? FilterValues.fromJson(fv) : null,
    );
  }

  @override
  Future<List<RommCollection>> collections() async {
    final r = await dio.get('/api/collections', options: auth());
    final list = r.data is List ? r.data as List : const [];
    return [
      for (final c in list)
        if (c is Map<String, dynamic>) RommCollection.fromJson(c),
    ];
  }

  @override
  Future<RommCollection> setFavourite(String gameId, bool favourite, {required int userId}) async {
    final own = (await collections()).where((c) => c.isFavorite && c.userId == userId);
    final fav = own.isNotEmpty ? own.first : await _createFavourites();
    final body = {
      'rom_ids': [int.parse(gameId)],
    };
    final r = favourite
        ? await dio.post('/api/collections/${fav.id}/roms', data: body, options: auth())
        : await dio.delete('/api/collections/${fav.id}/roms', data: body, options: auth());
    return RommCollection.fromJson(r.data as Map<String, dynamic>);
  }

  @override
  Future<Game?> randomGame({int? platformId}) async {
    final q = GalleryQuery(platformId: platformId);
    final first = await page(q, limit: 1);
    if (first.total == 0) return null;
    final pick = await page(q, offset: Random().nextInt(first.total), limit: 1);
    return pick.games.isEmpty ? null : pick.games.first;
  }

  @override
  Future<List<RomNote>> notes(String gameId) async {
    final r = await dio.get('/api/roms/$gameId/notes', options: auth());
    final data = r.data;
    final list = data is Map && data['items'] is List ? data['items'] as List : (data is List ? data : const []);
    return [
      for (final n in list)
        if (n is Map<String, dynamic>) RomNote.fromJson(n),
    ];
  }

  @override
  Future<void> addNote(String gameId, String title, String content) => dio.post(
    '/api/roms/$gameId/notes',
    data: {'title': title, 'content': content, 'is_public': false, 'tags': []},
    options: auth(),
  );

  @override
  Future<void> deleteNote(String gameId, int noteId) => dio.delete('/api/roms/$gameId/notes/$noteId', options: auth());

  Future<RommCollection> _createFavourites() async {
    final r = await dio.post(
      '/api/collections',
      queryParameters: {'is_favorite': true, 'is_public': false},
      data: FormData.fromMap({'name': 'Favorites', 'description': ''}),
      options: auth(),
    );
    return RommCollection.fromJson(r.data as Map<String, dynamic>);
  }
}
