// Adapted from Freegosy (MIT, © 2026 abduznik).
part of '../romm_service.dart';

/// Saves (`/api/saves`).
mixin _RommSaves on _RommBase {
  Future<List<SaveFile>> getSaves(String gameId) async {
    final response = await _dio.get('/api/saves', queryParameters: {'rom_id': gameId}, options: _authOptions);
    if (response.statusCode == 200) {
      final List<dynamic> items = (response.data is Map && response.data.containsKey('items'))
          ? response.data['items']
          : response.data as List<dynamic>;
      return items.map((item) => SaveFile.fromJson(item)).toList();
    }
    throw DioException(requestOptions: response.requestOptions, response: response, type: DioExceptionType.badResponse);
  }

  /// Uploads a save file to RomM.
  ///
  /// When [deviceId] is provided (RomM 4.9+), the server tracks sync state and
  /// returns 409 on conflict. [slot] groups saves into named categories.
  /// [autocleanup] + [autocleanupLimit] let the server prune old slot saves.
  /// [overwrite] bypasses server-side conflict detection (force-push).
  ///
  /// Returns `null` on a 409 conflict so callers can inspect the raw response;
  /// returns `true` on success; returns `false` on other errors.
  ///
  /// [emulator] is the emulator that made the save, as RomM and other
  /// clients name it (a RetroArch core like `pcsx_rearmed`, or an emulator
  /// like `duckstation`); RomM's in-browser player only offers saves tagged
  /// with its core. `gargosy` when unknown.
  /// [saved]: RomM's record of the uploaded save (its `id`), when it sent one.
  Future<({bool ok, Map<String, dynamic>? conflict, Map<String, dynamic>? saved})> uploadSave(
    String gameId,
    io.File saveFile, {
    String? emulator,
    String? slot,
    String? deviceId,
    bool autocleanup = false,
    int autocleanupLimit = 5,
    bool overwrite = false,
    io.File? screenshotFile,
    String? overrideFilename,
  }) async {
    try {
      final uploadFilename = overrideFilename ?? saveFile.uri.pathSegments.last;

      // Slot naming: always use 'gargosy' for consistency (Freegosy, which this
      // code comes from, used 'freegosy'; those saves still show and restore).
      // Previously used timestamped slots like 'freegosy-srm_2026-07-11_08-45-38'
      // which created duplicate records on RomM and caused the filename to be
      // corrupted with timestamps. RomM's autocleanup handles version pruning.
      // Do NOT add timestamps to the slot — it breaks save sync (issues #42, #28).
      final queryParams = <String, dynamic>{
        'rom_id': gameId,
        'emulator': emulator ?? 'gargosy',
        'slot': slot ?? 'gargosy',
      };
      // Autocleanup and overwrite are now available for ALL paths (not just 4.9+).
      // This ensures legacy RomM instances also get proper save management.
      if (deviceId != null) queryParams['device_id'] = deviceId;
      if (autocleanup) {
        queryParams['autocleanup'] = 'true';
        queryParams['autocleanup_limit'] = autocleanupLimit.toString();
      }
      if (overwrite) queryParams['overwrite'] = 'true';

      final formDataMap = <String, dynamic>{
        'saveFile': await MultipartFile.fromFile(saveFile.path, filename: uploadFilename),
      };
      if (screenshotFile != null && await screenshotFile.exists()) {
        formDataMap['screenshotFile'] = await MultipartFile.fromFile(
          screenshotFile.path,
          filename: screenshotFile.uri.pathSegments.last,
        );
      }

      final response = await _dio.post(
        '/api/saves',
        queryParameters: queryParams,
        data: FormData.fromMap(formDataMap),
        options: _authOptions.copyWith(
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 409) {
        final detail = response.data is Map ? (response.data['detail'] as Map<String, dynamic>?) : null;
        debugPrint('[RomM] uploadSave 409 conflict: $detail');
        return (ok: false, conflict: detail, saved: null);
      }

      final ok = response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
      final saved = ok && response.data is Map ? Map<String, dynamic>.from(response.data as Map) : null;
      return (ok: ok, conflict: null, saved: saved);
    } catch (e) {
      debugPrint('[RomM] uploadSave error: $e');
      return (ok: false, conflict: null, saved: null);
    }
  }

  /// Tells RomM that device [deviceId] has save [saveId] (POST
  /// /api/saves/{id}/downloaded), as a download would: RomM's device sync
  /// then doesn't take this device's next upload for a stale one. For a save
  /// this device already had byte for byte. False when it fails.
  Future<bool> confirmSaveDownloaded(int saveId, {required String deviceId}) async {
    try {
      final response = await _dio.post(
        '/api/saves/$saveId/downloaded',
        data: {'device_id': deviceId},
        options: _authOptions.copyWith(contentType: 'application/json', validateStatus: (s) => s != null && s < 500),
      );
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (e) {
      debugPrint('[RomM] confirmSaveDownloaded error: $e');
      return false;
    }
  }

  Future<bool> deleteSaves(List<int> saveIds) async {
    if (saveIds.isEmpty) return true;
    try {
      final response = await _dio.post(
        '/api/saves/delete',
        data: {'saves': saveIds},
        options: _authOptions.copyWith(contentType: 'application/json'),
      );
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (e) {
      debugPrint('[RomM] deleteSaves error: $e');
      return false;
    }
  }

  Future<void> pruneOldSaves(String gameId, {int keepCount = 5}) async {
    try {
      final saves = await getSavesList(gameId);
      // Gargosy's saves are the ones in its slot; their emulator tag names
      // the emulator that made them. Saves in Freegosy's slot are never pruned.
      final ownSaves = saves.where((s) => (s['slot']?.toString() ?? '') == 'gargosy').toList();
      if (ownSaves.length <= keepCount) return;

      final toDelete = ownSaves.sublist(keepCount);
      final idsToDelete = toDelete.map((s) => int.tryParse(s['id']?.toString() ?? '')).whereType<int>().toList();

      if (idsToDelete.isNotEmpty) {
        debugPrint('[RomM] Pruning ${idsToDelete.length} old saves for game $gameId');
        await deleteSaves(idsToDelete);
      }
    } catch (e) {
      debugPrint('[RomM] pruneOldSaves error: $e');
    }
  }

  /// Lists saves for a game, sorted newest-first.
  ///
  /// Pass [deviceId] (RomM 4.9+) to receive `device_syncs[]` with `is_current`
  /// on each save. Pass [slot] to filter to a specific slot.
  Future<List<Map<String, dynamic>>> getSavesList(String gameId, {String? deviceId, String? slot}) async =>
      await getSavesListOrNull(gameId, deviceId: deviceId, slot: slot) ?? [];

  /// Like [getSavesList], but null when the list couldn't be read (an error
  /// or a refused request), so a caller can tell that apart from no saves.
  Future<List<Map<String, dynamic>>?> getSavesListOrNull(String gameId, {String? deviceId, String? slot}) async {
    try {
      final params = <String, dynamic>{'rom_id': gameId};
      if (deviceId != null) params['device_id'] = deviceId;
      if (slot != null) params['slot'] = slot;

      final response = await _dio.get('/api/saves', queryParameters: params, options: _authOptions);
      if (response.statusCode != 200) return null;
      final List<dynamic> items = (response.data is Map && response.data.containsKey('items'))
          ? response.data['items']
          : (response.data is List ? response.data : []);
      final sorted = List<Map<String, dynamic>>.from(items.whereType<Map<String, dynamic>>());
      sorted.sort((a, b) {
        final ta = DateTime.tryParse(a['created_at']?.toString() ?? a['updated_at']?.toString() ?? '') ?? DateTime(0);
        final tb = DateTime.tryParse(b['created_at']?.toString() ?? b['updated_at']?.toString() ?? '') ?? DateTime(0);
        return tb.compareTo(ta);
      });
      return sorted;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getLatestSave(String gameId, {String? deviceId}) async {
    final items = await getSavesList(gameId, deviceId: deviceId);
    return items.isEmpty ? null : items.first;
  }

  /// Downloads save file bytes.
  ///
  /// Pass [deviceId] (RomM 4.9+) to trigger optimistic sync-record update on
  /// the server side (saves a separate /downloaded call).
  Future<Uint8List?> downloadSave(String saveUrl, {String? deviceId}) async {
    try {
      var url = saveUrl.startsWith('http') ? saveUrl : '${_normalizeBaseUrl(_config.baseUrl)}$saveUrl';
      // 4.9+: append device_id for optimistic sync record update
      if (deviceId != null) {
        final separator = url.contains('?') ? '&' : '?';
        url = '$url${separator}device_id=${Uri.encodeComponent(deviceId)}&optimistic=true';
      }
      final response = await _dio.get<List<int>>(url, options: _authOptions.copyWith(responseType: ResponseType.bytes));
      return (response.statusCode == 200 && response.data != null) ? Uint8List.fromList(response.data!) : null;
    } catch (e) {
      debugPrint('[RomM] downloadSave error: $e');
      return null;
    }
  }
}
