import 'dart:convert';

import 'package:dio/dio.dart';

import 'romm_library_api.dart';

/// Changing the user's own collections on RomM (#144): a game in or out,
/// a new one, renamed, shared, deleted. RomM lets only the owner do it.
abstract class CollectionEdits {
  /// Puts [gameId] in collection [collectionId], or takes it out; only that
  /// game changes (RomM's `/api/collections/{id}/roms`).
  Future<RommCollection> setIn(int collectionId, String gameId, bool inIt);

  /// A new collection named [name], [shared] or only the user's, holding
  /// [gameId] when given. Throws [CollectionEditException] when the user has
  /// one of that name.
  Future<RommCollection> create(String name, {bool shared = false, String? gameId});

  Future<RommCollection> rename(RommCollection c, String name);
  Future<RommCollection> setShared(int collectionId, bool shared);
  Future<void> delete(int collectionId);
}

/// What RomM refused, said for the player.
class CollectionEditException implements Exception {
  const CollectionEditException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RommCollectionEdits implements CollectionEdits {
  RommCollectionEdits(this.dio, this.auth);

  final Dio dio;
  final Options Function() auth;

  static RommCollection _read(Response<dynamic> r) => RommCollection.fromJson(r.data as Map<String, dynamic>);

  /// RomM's own reason when it gives one ("A collection named … exists").
  static Future<T> _said<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = data is Map ? data['detail'] : null;
      if (detail is String && detail.isNotEmpty) throw CollectionEditException(detail);
      if (e.response?.statusCode == 403) {
        throw const CollectionEditException('RomM lets only its owner change this collection.');
      }
      rethrow;
    }
  }

  @override
  Future<RommCollection> setIn(int collectionId, String gameId, bool inIt) => _said(() async {
    final body = {
      'rom_ids': [int.parse(gameId)],
    };
    final path = '/api/collections/$collectionId/roms';
    return _read(
      inIt ? await dio.post(path, data: body, options: auth()) : await dio.delete(path, data: body, options: auth()),
    );
  });

  @override
  Future<RommCollection> create(String name, {bool shared = false, String? gameId}) => _said(() async {
    final made = _read(
      await dio.post(
        '/api/collections',
        queryParameters: {'is_favorite': false, 'is_public': shared},
        data: FormData.fromMap({'name': name, 'description': ''}),
        options: auth(),
      ),
    );
    return gameId == null ? made : setIn(made.id, gameId, true);
  });

  @override
  Future<RommCollection> rename(RommCollection c, String name) => _said(() async {
    // RomM's update takes the whole game list; it's sent as it is.
    return _read(
      await dio.put(
        '/api/collections/${c.id}',
        data: FormData.fromMap({'name': name, 'rom_ids': jsonEncode(c.romIds.toList())}),
        options: auth(),
      ),
    );
  });

  @override
  Future<RommCollection> setShared(int collectionId, bool shared) => _said(() async {
    return _read(
      await dio.put('/api/collections/$collectionId/visibility', data: {'is_public': shared}, options: auth()),
    );
  });

  @override
  Future<void> delete(int collectionId) => _said(() => dio.delete('/api/collections/$collectionId', options: auth()));
}
