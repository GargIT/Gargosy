import 'dart:async';

import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';

/// A library of [all] games; records each query.
class FakeLibraryApi implements LibraryApi {
  FakeLibraryApi(this.all, {this.values = const FilterValues(genres: ['Action', 'Racing'], regions: ['USA'])});

  final List<Game> all;
  final FilterValues values;
  final queries = <(GalleryQuery, int)>[];

  /// Each page's limit, in order.
  final limits = <int>[];

  /// Whether each page asked for versions folded.
  final folded = <bool>[];
  Object? failWith;

  /// How long each page takes (a real server isn't instant).
  Duration delay = Duration.zero;

  /// Pages from this offset on fail (the server went away mid-scroll).
  int? failFromOffset;

  @override
  Future<GalleryPage> page(
    GalleryQuery q, {
    int offset = 0,
    int limit = RommLibraryApi.pageSize,
    bool withFilterValues = false,
    bool withCharIndex = false,
    bool foldVersions = false,
  }) async {
    queries.add((q, offset));
    folded.add(foldVersions);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failWith != null) throw failWith!;
    if (failFromOffset != null && offset >= failFromOffset!) throw Exception('SocketException: connection reset');
    var list = all.where((g) => q.search == null || g.name.toLowerCase().contains(q.search!.toLowerCase())).toList();
    if (q.genres.isNotEmpty) list = list.where((g) => g.genres.any(q.genres.contains)).toList();
    final slice = list.skip(offset).take(limit).toList();
    limits.add(limit);
    // As RomM: by name only, each first letter's offset in the whole list.
    Map<String, int>? index;
    if (withCharIndex && q.sort == GallerySort.name) {
      index = {};
      for (var i = 0; i < list.length; i++) {
        final c = list[i].name.toLowerCase();
        if (c.isNotEmpty) index.putIfAbsent(c[0], () => i);
      }
    }
    return GalleryPage(games: slice, total: list.length, filters: withFilterValues ? values : null, charIndex: index);
  }

  @override
  Future<List<RommCollection>> collections() async => const [];

  @override
  Future<Game?> randomGame({int? platformId}) async =>
      all.where((g) => platformId == null || g.platformId == platformId).firstOrNull;

  final notesById = <String, List<RomNote>>{};

  @override
  Future<List<RomNote>> notes(String gameId) async {
    if (failWith != null) throw failWith!;
    return notesById[gameId] ?? const [];
  }

  @override
  Future<void> addNote(String gameId, String title, String content) async {
    if (failWith != null) throw failWith!;
    (notesById[gameId] ??= []).add(RomNote(id: 99, title: title, content: content));
  }

  @override
  Future<void> deleteNote(String gameId, int noteId) async {
    if (failWith != null) throw failWith!;
    notesById[gameId]?.removeWhere((n) => n.id == noteId);
  }

  final favouriteCalls = <String>[];

  @override
  Future<RommCollection> setFavourite(String gameId, bool favourite, {required int userId}) async =>
      _favourite(gameId, favourite, userId);

  Future<RommCollection> _favourite(String gameId, bool favourite, int userId) async {
    favouriteCalls.add(gameId);
    if (failWith != null) throw failWith!;
    if (favouriteDelay != null) await favouriteDelay!.future;
    return RommCollection(
      id: 1,
      name: 'Favorites',
      isFavorite: true,
      userId: userId,
      romIds: favourite ? {int.parse(gameId)} : const {},
    );
  }

  /// When set, setFavourite waits for it (a slow server).
  Completer<void>? favouriteDelay;
}
