// Adapted from Freegosy (MIT, © 2026 abduznik).
part of '../romm_service.dart';

/// Gargosy (#92): other players' saves and states, and sharing the player's own.
mixin _RommSharing on _RommBase {
  /// Gargosy (#92): other players' public saves of a game. RomM's save list
  /// holds only the caller's own; the game itself (`all_user_saves`) adds
  /// every other user's public ones, with `username` and `user_avatar_path`.
  /// Those of [exceptUserId] (the profile's own) are left out. Null when the
  /// game couldn't be read.
  Future<List<Map<String, dynamic>>?> getSharedSavesOrNull(String gameId, {required int exceptUserId}) =>
      _sharedOf(gameId, 'all_user_saves', exceptUserId);

  /// Gargosy (#92): other players' public states of a game, as
  /// [getSharedSavesOrNull] (`all_user_states`).
  Future<List<Map<String, dynamic>>?> getSharedStatesOrNull(String gameId, {required int exceptUserId}) =>
      _sharedOf(gameId, 'all_user_states', exceptUserId);

  /// Gargosy (#92): shares the player's own save with every other user of
  /// RomM, or stops ([shared] false): `PUT /api/saves/{id}/visibility`,
  /// owner only. Whether RomM took it.
  Future<bool> setSaveShared(int saveId, bool shared) => _setShared('saves', saveId, shared);

  /// Gargosy (#92): the same for the player's own state.
  Future<bool> setStateShared(int stateId, bool shared) => _setShared('states', stateId, shared);

  Future<bool> _setShared(String kind, int id, bool shared) async {
    try {
      final response = await _dio.put('/api/$kind/$id/visibility', data: {'is_public': shared}, options: _authOptions);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[RomM] $kind/$id not ${shared ? 'shared' : 'made private'}: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>?> _sharedOf(String gameId, String key, int exceptUserId) async {
    try {
      final response = await _dio.get('/api/roms/$gameId', options: _authOptions);
      if (response.statusCode != 200 || response.data is! Map) return null;
      final items = (response.data as Map)[key];
      return [
        for (final item in items is List ? items : const [])
          if (item is Map<String, dynamic> && (item['user_id'] as num?)?.toInt() != exceptUserId) item,
      ];
    } catch (_) {
      return null;
    }
  }
}
