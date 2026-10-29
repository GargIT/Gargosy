// Adapted from Freegosy (MIT, © 2026 abduznik).
part of '../romm_service.dart';

/// The RomM user: RetroAchievements link and progress, avatars, permissions.
mixin _RommUsers on _RommBase {
  /// The current user's RetroAchievements progress as synced by RomM
  /// (`ra_progression` on /api/users/me), keyed by RA game ID. Empty when the
  /// server has no RA key or the user hasn't linked an RA username in RomM.
  Future<Map<int, Map<String, dynamic>>> getRetroAchievementsProgression() async =>
      await getRetroAchievementsProgressionOrNull() ?? {};

  /// Gargosy (#189): like [getRetroAchievementsProgression], but null when
  /// RomM couldn't be asked, so a session can tell that from no progress.
  Future<Map<int, Map<String, dynamic>>?> getRetroAchievementsProgressionOrNull() async {
    try {
      final response = await _dio.get('/api/users/me', options: _authOptions);
      final data = response.data;
      final progression = data is Map ? data['ra_progression'] : null;
      final results = progression is Map ? progression['results'] : null;
      if (results is! List) return {};
      return {
        for (final r in results.whereType<Map<String, dynamic>>())
          if (r['rom_ra_id'] is int) r['rom_ra_id'] as int: r,
      };
    } catch (_) {
      return null;
    }
  }

  /// The current RomM user's id and the RetroAchievements username linked
  /// on their RomM profile (null if none). Null when the request fails.
  Future<({int id, String? raUsername})?> getRetroAchievementsLink() async {
    try {
      final response = await _dio.get('/api/users/me', options: _authOptions);
      final data = response.data;
      if (data is! Map || data['id'] is! int) return null;
      final ra = data['ra_username']?.toString();
      return (id: data['id'] as int, raUsername: (ra == null || ra.isEmpty) ? null : ra);
    } catch (e) {
      debugPrint('[RomM] getRetroAchievementsLink error: $e');
      return null;
    }
  }

  /// Sets [raUsername] on RomM user [userId]'s profile (PUT /api/users/{id},
  /// form field `ra_username`). Throws on failure so the caller can report it.
  Future<void> setRetroAchievementsUsername(int userId, String raUsername) async {
    await _dio.put('/api/users/$userId', data: FormData.fromMap({'ra_username': raUsername}), options: _authOptions);
  }

  /// Asks RomM to re-sync [userId]'s RetroAchievements progress
  /// (POST /api/users/{id}/ra/refresh). RomM fetches the whole history from
  /// RA, so this can take a while. Returns false if RomM refused or failed
  /// (e.g. an API token without the `me.write` scope).
  Future<bool> refreshRetroAchievements(int userId) => _refreshRetroAchievements(userId, incremental: false);

  /// Gargosy (#189): as [refreshRetroAchievements], reading only what's new
  /// since RomM's last read (after a session).
  Future<bool> refreshNewRetroAchievements(int userId) => _refreshRetroAchievements(userId, incremental: true);

  Future<bool> _refreshRetroAchievements(int userId, {required bool incremental}) async {
    try {
      await _dio.post(
        '/api/users/$userId/ra/refresh',
        data: {'incremental': incremental},
        options: _authOptions.copyWith(contentType: 'application/json', receiveTimeout: const Duration(minutes: 3)),
      );
      return true;
    } catch (e) {
      debugPrint('[RomM] refreshRetroAchievements error: $e');
      return false;
    }
  }

  /// Gargosy (#180): a RomM user's avatar (`/api/users/{id}/avatar`, which
  /// asks for the token); null when they have none or it couldn't be read.
  Future<Uint8List?> userAvatar(int userId) async {
    try {
      final r = await _dio.get<List<int>>(
        '/api/users/$userId/avatar',
        options: _authOptions.copyWith(responseType: ResponseType.bytes),
      );
      final bytes = r.data;
      return bytes == null || bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } catch (e) {
      debugPrint('[RomM] avatar of user $userId not read: $e');
      return null;
    }
  }

  /// Gargosy: whether the user may delete games on RomM: RomM 5.4's
  /// `/api/permissions/me` (an admin, or the `rom.delete` action), else on an
  /// older RomM an admin's or editor's role. False when RomM can't say.
  Future<bool> canDeleteGames() async {
    try {
      final data = (await _dio.get('/api/permissions/me', options: _authOptions)).data;
      if (data is! Map) return false;
      final grants = data['grants'];
      return data['is_admin'] == true || (grants is List && grants.any((g) => g is Map && g['action'] == 'rom.delete'));
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        debugPrint('[RomM] permissions not read: ${e.response?.statusCode ?? e.type}');
        return false;
      }
    } catch (e) {
      debugPrint('[RomM] permissions not read: $e');
      return false;
    }
    try {
      final data = (await _dio.get('/api/users/me', options: _authOptions)).data;
      final role = data is Map ? data['role'] : null;
      return role == 'admin' || role == 'editor';
    } catch (e) {
      debugPrint('[RomM] role not read: $e');
      return false;
    }
  }
}
