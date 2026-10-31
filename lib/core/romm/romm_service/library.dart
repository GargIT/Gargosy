// Adapted from Freegosy (MIT, © 2026 abduznik).
part of '../romm_service.dart';

/// Games, platforms, collections, a game's props and notes, deleting a game.
mixin _RommLibrary on _RommBase {
  Future<Game?> getGame(String id) async {
    try {
      final response = await _dio.get('/api/roms/$id', options: _authOptions);
      if (response.statusCode == 200) return Game.fromJson(response.data);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Gargosy (#232): the game's manual, [pathManual] (`Game.pathManual`)
  /// under RomM's resources. Throws when RomM can't give it.
  Future<Uint8List> downloadManual(String pathManual) async {
    final path = pathManual.startsWith('/') ? pathManual.substring(1) : pathManual;
    final response = await _dio.get<List<int>>(
      '/assets/romm/resources/$path',
      options: _authOptions.copyWith(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 2)),
    );
    final data = response.data;
    if (response.statusCode != 200 || data == null || data.isEmpty) {
      throw StateError('RomM sent no manual (${response.statusCode}).');
    }
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  /// Gargosy (#224): the age ratings across the library, as RomM's
  /// `age_ratings` filter takes them (`filter_values.age_ratings`), in one
  /// small request. Throws when RomM can't be read.
  Future<List<String>> getLibraryAgeRatings() async {
    final r = await _dio.get(
      '/api/roms',
      queryParameters: {'limit': 1, 'with_filter_values': true},
      options: _authOptions,
    );
    final data = r.data;
    final values = data is Map && data['filter_values'] is Map ? (data['filter_values'] as Map)['age_ratings'] : null;
    return [
      for (final v in values is List ? values : const [])
        if (v is String && v.trim().isNotEmpty) v,
    ];
  }

  Future<List<Platform>> getPlatforms() async {
    final response = await _dio.get('/api/platforms', options: _authOptions);
    if (response.statusCode == 200) {
      final List<dynamic> items = (response.data is Map && response.data.containsKey('items'))
          ? response.data['items']
          : response.data as List<dynamic>;
      return items.map((item) => Platform.fromJson(item)).toList();
    }
    throw DioException(requestOptions: response.requestOptions, response: response, type: DioExceptionType.badResponse);
  }

  Future<List<Map<String, dynamic>>> getCollections() async {
    try {
      final response = await _dio.get('/api/collections', options: _authOptions);
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data is List ? response.data : [];
        return data.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// [small]: RomM's small cover (240 × 360), for grids and shelves.
  String? resolveCoverUrl(Game game, {bool small = false}) {
    final host = _normalizeBaseUrl(_config.baseUrl);
    String? path = small ? game.pathCoverSmall ?? game.pathCoverLarge : game.pathCoverLarge ?? game.pathCoverSmall;
    if (path != null && path.isNotEmpty) return path.startsWith('http') ? path : "$host$path";
    String? url = game.urlCover;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('//')) return "https:$url";
      return url;
    }
    return null;
  }

  Future<List<Game>> getGames(String platformId) async {
    return _fetchPaginatedGames({'platform_id': int.parse(platformId)});
  }

  Future<List<Game>> getAllGames({String? platformId}) async {
    final params = platformId != null ? {'platform_id': int.parse(platformId)} : <String, dynamic>{};
    return _fetchPaginatedGames(params);
  }

  Future<List<Game>> getRecentlyAdded({int limit = 15}) async {
    try {
      final response = await _dio.get(
        '/api/roms',
        queryParameters: {
          'limit': limit,
          'order_by': 'id',
          'order_dir': 'desc',
          'with_char_index': false,
          'with_filter_values': false,
        },
        options: _authOptions,
      );
      if (response.statusCode == 200) {
        final List<dynamic> items = response.data is Map
            ? (response.data['items'] ?? [])
            : (response.data is List ? response.data : []);
        return items.map((e) => Game.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Game>> getRecentlyPlayed({int limit = 15}) async {
    try {
      final response = await _dio.get(
        '/api/roms',
        queryParameters: {
          'limit': limit,
          'order_by': 'last_played',
          'order_dir': 'desc',
          'last_played': true,
          'with_char_index': false,
          'with_filter_values': false,
        },
        options: _authOptions,
      );
      if (response.statusCode == 200) {
        final List<dynamic> items = response.data is Map
            ? (response.data['items'] ?? [])
            : (response.data is List ? response.data : []);
        return items.map((e) => Game.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Game>> searchRoms({String? sha1, String? md5, String? search, String? platformId}) async {
    final params = <String, dynamic>{'limit': 50, 'offset': 0, 'with_char_index': false, 'with_filter_values': false};
    if (sha1 != null) params['sha1'] = sha1;
    if (md5 != null) params['md5'] = md5;
    if (search != null) params['search_term'] = search;
    if (platformId != null) params['platform_id'] = platformId;

    try {
      final response = await _dio.get('/api/roms', queryParameters: params, options: _authOptions);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.data is Map ? response.data : {'items': response.data};
        final List<dynamic> items = data['items'] ?? [];
        return items.map((e) => Game.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[RomM] searchRoms error: $e');
      return [];
    }
  }

  Future<({List<Game> games, int total})> getGamesPage({
    int offset = 0,
    int limit = 50,
    String? platformId,
    String? search,
    List<String> genres = const [],
    List<String> regions = const [],
    List<String> languages = const [],
    List<String> collections = const [],
    List<String> statuses = const [],
    bool? lastPlayed,
    bool withCharIndex = false,
    bool withFilterValues = false,
  }) async {
    final params = <String, dynamic>{
      'limit': limit,
      'offset': offset,
      'order_by': 'name',
      'order_dir': 'asc',
      'with_char_index': withCharIndex,
      'with_filter_values': withFilterValues,
    };
    if (lastPlayed != null) params['last_played'] = lastPlayed;
    if (platformId != null) params['platform_ids'] = [int.parse(platformId)];
    if (search != null && search.isNotEmpty) params['search_term'] = search;
    if (genres.isNotEmpty) params['genres'] = genres;
    if (regions.isNotEmpty) params['regions'] = regions;
    if (languages.isNotEmpty) params['languages'] = languages;
    if (collections.isNotEmpty) params['collection_id'] = int.tryParse(collections.first);
    if (statuses.isNotEmpty) {
      params['statuses'] = statuses;
      params['statuses_logic'] = 'any';
    }

    final response = await _dio.get('/api/roms', queryParameters: params, options: _authOptions);
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = response.data is Map ? response.data : {'items': response.data};
      final List<dynamic> items = data['items'] ?? [];
      final int totalCount = (data['total'] as num?)?.toInt() ?? items.length;
      return (games: items.map((e) => Game.fromJson(e)).toList(), total: totalCount);
    }
    throw DioException(requestOptions: response.requestOptions, response: response, type: DioExceptionType.badResponse);
  }

  Future<List<Game>> _fetchPaginatedGames(Map<String, dynamic> params) async {
    int offset = 0;
    const int limit = 100;
    List<Game> allGames = [];
    int total = 0;
    do {
      final response = await _dio.get(
        '/api/roms',
        queryParameters: {...params, 'limit': limit, 'offset': offset},
        options: _authOptions,
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.data is Map ? response.data : {'items': response.data};
        final List<dynamic> items = data['items'] ?? [];
        total = data['total'] ?? items.length;
        allGames.addAll(items.map((item) => Game.fromJson(item)).toList());
        offset += limit;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
        );
      }
    } while (allGames.length < total && offset < total);
    return allGames;
  }

  Future<Game?> getRandomGame() async {
    try {
      final countResponse = await _dio.get(
        '/api/roms',
        queryParameters: {
          'limit': 1,
          'offset': 0,
          'order_by': 'name',
          'order_dir': 'asc',
          'with_char_index': false,
          'with_filter_values': false,
        },
        options: _authOptions,
      );
      if (countResponse.statusCode != 200) return null;
      final total = (countResponse.data is Map ? countResponse.data['total'] : null) as int? ?? 0;
      if (total == 0) return null;
      final response = await _dio.get(
        '/api/roms',
        queryParameters: {
          'limit': 1,
          'offset': Random().nextInt(total),
          'order_by': 'name',
          'order_dir': 'asc',
          'with_char_index': false,
          'with_filter_values': false,
        },
        options: _authOptions,
      );
      final items = (response.data is Map ? response.data['items'] : null) as List<dynamic>? ?? [];
      return items.isEmpty ? null : Game.fromJson(items.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String getDownloadUrl(Game game) {
    if (game.fileUrl != null && game.fileUrl!.isNotEmpty) {
      final host = _normalizeBaseUrl(_config.baseUrl);
      return game.fileUrl!.startsWith('http') ? game.fileUrl! : '$host${game.fileUrl}';
    }
    final baseUrl = _normalizeBaseUrl(_config.baseUrl);
    final name = game.fileName ?? game.fsName ?? game.name;
    String encoded = Uri.encodeComponent(name).replaceAll("'", "%27").replaceAll("(", "%28").replaceAll(")", "%29");
    if (encoded.length > 100) {
      final ext = p.extension(name);
      final stem = p.basenameWithoutExtension(name);
      encoded = Uri.encodeComponent('${stem.substring(0, min(stem.length, 50))}$ext')
          .replaceAll("'", "%27")
          .replaceAll("(", "%28")
          .replaceAll(")", "%29");
    }
    final url = '$baseUrl/api/roms/${game.id}/content/$encoded';

    // Per RomM's API, the path filename above is only the zip output name -
    // it does not select which file gets served. The real selector is the
    // `file_ids` query param, built from files[] (each entry's real database
    // id). Passing it explicitly avoids relying on the server to guess the
    // right file from a reconstructed name, which is unreliable for
    // single-file-foldered roms (see issue #44).
    if (game.files.isNotEmpty) {
      final ids = game.files.map((f) => f['id']).where((id) => id != null).map((id) => id.toString()).toList();
      if (ids.isNotEmpty) {
        return '$url?file_ids=${ids.join(',')}';
      }
    }
    return url;
  }

  /// Gargosy: deletes a game from RomM's library (`POST /api/roms/delete`),
  /// with [fromServerDisk] its file or folder on RomM's server too. Every
  /// player's saves and states of it go with it.
  Future<RomDeleteResult> deleteGame(int romId, {required bool fromServerDisk}) async {
    try {
      final r = await _dio.post(
        '/api/roms/delete',
        data: {
          'roms': [romId],
          'delete_from_fs': [if (fromServerDisk) romId],
        },
        options: _authOptions.copyWith(contentType: 'application/json'),
      );
      final data = r.data;
      final ok = data is Map ? (data['successful_items'] as num?)?.toInt() : null;
      if (ok == 1 || (ok == null && r.statusCode == 200)) return RomDeleteResult.deleted;
      debugPrint('[RomM] rom $romId not deleted: ${data is Map ? data['errors'] : r.statusCode}');
      return RomDeleteResult.failed;
    } on DioException catch (e) {
      debugPrint('[RomM] rom $romId not deleted: ${e.response?.statusCode ?? e.type}');
      return e.response?.statusCode == 403 ? RomDeleteResult.notAllowed : RomDeleteResult.failed;
    } catch (e) {
      debugPrint('[RomM] rom $romId not deleted: $e');
      return RomDeleteResult.failed;
    }
  }

  Future<bool> updateRomProps(
    String romId, {
    bool? backlogged,
    bool? nowPlaying,
    int? rating,
    String? status,
    int? completion,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (backlogged != null) data['backlogged'] = backlogged;
      if (nowPlaying != null) data['now_playing'] = nowPlaying;
      if (rating != null) data['rating'] = rating;
      if (status != null) data['status'] = status.toLowerCase();
      if (completion != null) data['completion'] = completion;
      // RomM 5.4 takes the fields as the body itself (its RomUserData) and
      // ignores the rest, so the older `{"data": {...}}` alone saved nothing;
      // older RomM reads only `data`. Both go, so either one saves.
      final response = await _dio.put(
        '/api/roms/$romId/props',
        data: {...data, 'data': data, 'update_last_played': false, 'remove_last_played': false},
        options: Options(
          headers: Map<String, dynamic>.from(_authOptions.headers ?? {})..['Content-Type'] = 'application/json',
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<List<RomNote>> getRomNotes(String romId) async {
    try {
      final response = await _dio.get('/api/roms/$romId/notes', options: _authOptions);
      if (response.statusCode == 200) {
        final List<dynamic> items = (response.data is Map && response.data.containsKey('items'))
            ? response.data['items']
            : response.data as List<dynamic>;
        return items.map((item) => RomNote.fromJson(item)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> createRomNote(String romId, String title, String content) async {
    try {
      final response = await _dio.post(
        '/api/roms/$romId/notes',
        data: {'title': title, 'content': content, 'is_public': false, 'tags': []},
        options: _authOptions.copyWith(contentType: 'application/json'),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteRomNote(String romId, int noteId) async {
    try {
      final response = await _dio.delete('/api/roms/$romId/notes/$noteId', options: _authOptions);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }
}
