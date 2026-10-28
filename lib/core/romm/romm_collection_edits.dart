import 'dart:convert';

import 'package:dio/dio.dart';

import 'romm_library_api.dart';
import '../../l10n/tr.dart';

/// Changing the user's own collections on RomM (#144): a game in or out,
/// a new one, renamed, shared, deleted; smart ones too (#188). RomM lets only
/// the owner do it.
abstract class CollectionEdits {
  /// Puts [gameId] in collection [collectionId], or takes it out; only that
  /// game changes (RomM's `/api/collections/{id}/roms`).
  Future<RommCollection> setIn(int collectionId, String gameId, bool inIt);

  /// A new collection named [name], [shared] or only the user's, holding
  /// [gameId] when given. Throws [CollectionEditException] when the user has
  /// one of that name.
  Future<RommCollection> create(String name, {bool shared = false, String? gameId});

  /// A new smart collection named [name] holding the games that match
  /// [criteria] (`/api/roms`'s names; see `smartCriteriaOf`).
  Future<RommCollection> createSmart(String name, Map<String, dynamic> criteria, {bool shared = false});

  /// Regular or smart, by [RommCollection.kind]; a smart one keeps its filters.
  Future<RommCollection> rename(RommCollection c, String name);
  Future<RommCollection> setShared(RommCollection c, bool shared);
  Future<void> delete(RommCollection c);
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

  static RommCollection _read(Response<dynamic> r, [CollectionKind kind = CollectionKind.regular]) =>
      RommCollection.fromJson(r.data as Map<String, dynamic>, kind: kind);

  static String _path(RommCollection c) =>
      c.kind == CollectionKind.smart ? '/api/collections/smart/${c.id}' : '/api/collections/${c.id}';

  /// RomM's own reason when it gives one ("A collection named … exists").
  static Future<T> _said<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = data is Map ? data['detail'] : null;
      if (detail is String && detail.isNotEmpty) throw CollectionEditException(detail);
      if (e.response?.statusCode == 403) {
        throw CollectionEditException(tr('RomM lets only its owner change this collection.'));
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
  Future<RommCollection> createSmart(String name, Map<String, dynamic> criteria, {bool shared = false}) =>
      _said(() async {
        return _read(
          await dio.post(
            '/api/collections/smart',
            queryParameters: {'is_public': shared},
            data: FormData.fromMap({'name': name, 'description': '', 'filter_criteria': jsonEncode(criteria)}),
            options: auth(),
          ),
          CollectionKind.smart,
        );
      });

  @override
  Future<RommCollection> rename(RommCollection c, String name) => _said(() async {
    if (c.kind == CollectionKind.smart) {
      // Without filter_criteria RomM keeps the stored ones.
      return _read(
        await dio.put(_path(c), data: FormData.fromMap({'name': name}), options: auth()),
        CollectionKind.smart,
      );
    }
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
  Future<RommCollection> setShared(RommCollection c, bool shared) => _said(() async {
    return _read(await dio.put('${_path(c)}/visibility', data: {'is_public': shared}, options: auth()), c.kind);
  });

  @override
  Future<void> delete(RommCollection c) => _said(() => dio.delete(_path(c), options: auth()));
}
