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
  /// RomM's search order (relevance: an empty `order_by` with a search term);
  /// offered only while searching (#132).
  bestMatch('', 'Best match', false),
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

/// What a gallery shows: its scope (a platform, a collection of any kind,
/// favourites or a search), its sort and its filters.
@immutable
class GalleryQuery {
  const GalleryQuery({
    this.platformId,
    this.collectionId,
    this.smartCollectionId,
    this.virtualCollectionId,
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

  /// A smart collection's id (RomM picks its games by its filters).
  final int? smartCollectionId;

  /// A virtual collection's id (RomM's, from the games' metadata: a
  /// franchise, genre, company …).
  final String? virtualCollectionId;
  final bool favourites;

  /// The scope is one collection, of any kind.
  bool get inCollection => collectionId != null || smartCollectionId != null || virtualCollectionId != null;
  final String? search;
  final GallerySort sort;
  final bool descending;
  final Set<String> genres;
  final Set<String> regions;

  /// Only games the user has played (Home's "Continue playing").
  final bool lastPlayedOnly;

  GalleryQuery copyWith({
    Object? platformId = _keep,
    Object? search = _keep,
    GallerySort? sort,
    bool? descending,
    Set<String>? genres,
    Set<String>? regions,
  }) => GalleryQuery(
    platformId: identical(platformId, _keep) ? this.platformId : platformId as int?,
    collectionId: collectionId,
    smartCollectionId: smartCollectionId,
    virtualCollectionId: virtualCollectionId,
    favourites: favourites,
    search: identical(search, _keep) ? this.search : search as String?,
    sort: sort ?? this.sort,
    descending: descending ?? this.descending,
    genres: genres ?? this.genres,
    regions: regions ?? this.regions,
    lastPlayedOnly: lastPlayedOnly,
  );

  /// This query searching for [term] (blank: nothing). Best match never
  /// stays without a term: it goes back to Name. With [bestMatch] (Search,
  /// #132) a term typed into an empty box sorts by Best match, unless a sort
  /// other than Name was picked.
  GalleryQuery withSearch(String? term, {bool bestMatch = false}) {
    final t = term?.trim() ?? '';
    final next = copyWith(search: t.isEmpty ? null : t);
    if (t.isEmpty) {
      return sort == GallerySort.bestMatch ? next.copyWith(sort: GallerySort.name, descending: false) : next;
    }
    final wasEmpty = search?.trim().isEmpty ?? true;
    if (bestMatch && wasEmpty && sort == GallerySort.name && !descending) {
      return next.copyWith(sort: GallerySort.bestMatch);
    }
    return next;
  }

  bool get hasFilters => genres.isNotEmpty || regions.isNotEmpty;

  /// Only the scope: no search, sort or filters.
  GalleryQuery get scopeOnly => GalleryQuery(
    platformId: platformId,
    collectionId: collectionId,
    smartCollectionId: smartCollectionId,
    virtualCollectionId: virtualCollectionId,
    favourites: favourites,
    lastPlayedOnly: lastPlayedOnly,
  );

  Map<String, dynamic> toParams({
    required int offset,
    required int limit,
    bool withFilterValues = false,
    bool withCharIndex = false,
    bool foldVersions = false,
  }) {
    final term = search?.trim() ?? '';
    return {
      'offset': offset,
      'limit': limit,
      'order_by': sort.field,
      'order_dir': descending ? 'desc' : 'asc',
      // Each first letter's offset in this order, for the A–Z rail (by name only).
      'with_char_index': withCharIndex,
      // RomM builds the ordered id list of the whole result set unless told
      // not to; Gargosy never uses it.
      'with_rom_id_index': false,
      'with_filter_values': withFilterValues,
      // A game's versions (regions, revisions) as one entry, with the rest in its `sibling_roms`.
      if (foldVersions) 'group_by_meta_id': true,
      if (lastPlayedOnly) 'last_played': true,
      if (platformId != null) 'platform_ids': [platformId],
      if (collectionId != null) 'collection_id': collectionId,
      if (smartCollectionId != null) 'smart_collection_id': smartCollectionId,
      if (virtualCollectionId != null) 'virtual_collection_id': virtualCollectionId,
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
      other.smartCollectionId == smartCollectionId &&
      other.virtualCollectionId == virtualCollectionId &&
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
    smartCollectionId,
    virtualCollectionId,
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
  const FilterValues({this.genres = const [], this.regions = const [], this.platforms = const []});
  final List<String> genres;
  final List<String> regions;

  /// The ids of the platforms the scope's games are on (RomM 5.4).
  final List<int> platforms;

  static List<String> _list(Object? v) => [
    for (final s in (v is List ? v : const []))
      if (s is String && s.isNotEmpty) s,
  ]..sort();

  factory FilterValues.fromJson(Map<String, dynamic> json) => FilterValues(
    genres: _list(json['genres']),
    regions: _list(json['regions']),
    platforms: [
      for (final id in (json['platforms'] is List ? json['platforms'] as List : const []))
        if (id is int) id,
    ],
  );
}

class GalleryPage {
  const GalleryPage({required this.games, required this.total, this.filters, this.charIndex});
  final List<Game> games;
  final int total;
  final FilterValues? filters;

  /// RomM's `char_index`: a first character (lowercase, leading articles
  /// dropped) → the offset of its first game in this order. Asked for only.
  final Map<String, int>? charIndex;
}

/// A collection's kind, as RomM has them: one the players made, a smart one
/// (games picked by its filters) or a virtual one (RomM's own, from the
/// games' metadata).
enum CollectionKind { regular, smart, virtual }

/// The types of RomM's virtual collections, in the order Gargosy shows them,
/// with their names (RomM's `type`).
const virtualCollectionTypes = {
  'collection': 'Series',
  'franchise': 'Franchise',
  'genre': 'Genre',
  'mode': 'Play mode',
  'company': 'Company',
};

class RommCollection {
  const RommCollection({
    required this.id,
    required this.name,
    this.kind = CollectionKind.regular,
    this.virtualId,
    this.virtualType,
    this.description = '',
    this.romIds = const {},
    this.romCount = 0,
    this.coverPath,
    this.coverPaths = const [],
    this.isFavorite = false,
    this.isPublic = false,
    this.userId,
    this.ownerUsername,
    this.updatedAt,
    this.filterSummary,
  });

  /// RomM's id of a regular or smart collection; 0 for a virtual one.
  final int id;
  final String name;
  final CollectionKind kind;

  /// A virtual collection's id and type (`genre` …).
  final String? virtualId;
  final String? virtualType;
  final String description;
  final Set<int> romIds;
  final int romCount;
  final String? coverPath;

  /// A few of its games' covers, for the tile's mosaic.
  final List<String> coverPaths;
  final bool isFavorite;
  final bool isPublic;
  final int? userId;
  final String? ownerUsername;
  final DateTime? updatedAt;

  /// A smart collection's filters in words (RomM's `filter_summary`).
  final String? filterSummary;

  /// One key for every collection of every kind.
  String get key => kind == CollectionKind.virtual ? 'virtual-$virtualId' : '${kind.name}-$id';

  /// The gallery of its games.
  GalleryQuery get query => switch (kind) {
    _ when isFavorite => const GalleryQuery(favourites: true),
    CollectionKind.regular => GalleryQuery(collectionId: id),
    CollectionKind.smart => GalleryQuery(smartCollectionId: id),
    CollectionKind.virtual => GalleryQuery(virtualCollectionId: virtualId),
  };

  static List<String> _paths(Object? v) => [
    for (final s in (v is List ? v : const []))
      if (s is String && s.isNotEmpty) s,
  ];

  factory RommCollection.fromJson(Map<String, dynamic> json, {CollectionKind kind = CollectionKind.regular}) {
    final ids = {
      for (final i in (json['rom_ids'] is List ? json['rom_ids'] as List : const []))
        if (i is int) i,
    };
    final small = _paths(json['path_covers_small']);
    final virtual = kind == CollectionKind.virtual;
    return RommCollection(
      id: virtual || json['id'] is! int ? 0 : json['id'] as int,
      name: json['name'] as String? ?? '',
      kind: kind,
      virtualId: virtual ? '${json['id']}' : null,
      virtualType: virtual ? json['type'] as String? : null,
      description: json['description'] as String? ?? '',
      romIds: ids,
      romCount: json['rom_count'] is int ? json['rom_count'] as int : ids.length,
      coverPath: (json['path_cover_large'] ?? json['path_cover_small']) as String?,
      coverPaths: small.isNotEmpty ? small : _paths(json['path_covers_large']),
      isFavorite: json['is_favorite'] == true,
      isPublic: json['is_public'] == true,
      userId: json['user_id'] as int?,
      ownerUsername: json['owner_username'] as String?,
      updatedAt: json['updated_at'] is String ? DateTime.tryParse(json['updated_at'] as String) : null,
      filterSummary: json['filter_summary'] as String?,
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
    bool withCharIndex = false,
    bool foldVersions = false,
  });
  Future<List<RommCollection>> collections();

  /// The smart collections the user can see.
  Future<List<RommCollection>> smartCollections();

  /// RomM's virtual collections of one [type] (`genre` … in
  /// [virtualCollectionTypes]).
  Future<List<RommCollection>> virtualCollections(String type);

  /// Adds [gameId] to (or removes it from) the user's own favourites, creating
  /// that collection first when the user has none.
  Future<RommCollection> setFavourite(String gameId, bool favourite, {required int userId});

  /// A random game of the library, of one platform with [platformId] or of
  /// the gallery [within]; null when there is none.
  Future<Game?> randomGame({int? platformId, GalleryQuery? within});

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
    bool withCharIndex = false,
    bool foldVersions = false,
  }) async {
    final r = await dio.get(
      '/api/roms',
      queryParameters: q.toParams(
        offset: offset,
        limit: limit,
        withFilterValues: withFilterValues,
        withCharIndex: withCharIndex,
        foldVersions: foldVersions,
      ),
      options: auth(),
    );
    final data = r.data as Map<String, dynamic>;
    final games = [
      for (final g in (data['items'] as List? ?? const []))
        if (g is Map<String, dynamic>) Game.fromJson(g),
    ];
    final total = data['total'] is int ? data['total'] as int : offset + games.length;
    final fv = data['filter_values'];
    final ci = data['char_index'];
    return GalleryPage(
      games: games,
      total: total,
      filters: withFilterValues && fv is Map<String, dynamic> ? FilterValues.fromJson(fv) : null,
      charIndex: withCharIndex && ci is Map
          ? {
              for (final e in ci.entries)
                if (e.key is String && e.value is int) e.key as String: e.value as int,
            }
          : null,
    );
  }

  @override
  Future<List<RommCollection>> collections() => _list('/api/collections', CollectionKind.regular);

  @override
  Future<List<RommCollection>> smartCollections() => _list('/api/collections/smart', CollectionKind.smart);

  @override
  Future<List<RommCollection>> virtualCollections(String type) =>
      _list('/api/collections/virtual', CollectionKind.virtual, {'type': type});

  Future<List<RommCollection>> _list(String path, CollectionKind kind, [Map<String, dynamic>? params]) async {
    final r = await dio.get(path, queryParameters: params, options: auth());
    final list = r.data is List ? r.data as List : const [];
    return [
      for (final c in list)
        if (c is Map<String, dynamic>) RommCollection.fromJson(c, kind: kind),
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
  Future<Game?> randomGame({int? platformId, GalleryQuery? within}) async {
    final q = within ?? GalleryQuery(platformId: platformId);
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
