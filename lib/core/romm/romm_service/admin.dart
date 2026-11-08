part of '../romm_service.dart';

/// A RomM admin's tools (#245): scan the library, upload a game, fix a
/// game's metadata match. Shown only with [RommRights].
mixin _RommAdmin on _RommBase {
  /// The size of each piece of an upload, as RomM's web UI sends them
  /// (RomM takes at most 64 MB).
  static const uploadChunkBytes = 10 * 1024 * 1024;

  Options get _adminOptions => _authOptions.copyWith(validateStatus: (s) => s != null && s < 600);

  /// What the profile's RomM user may change; [RommRights.none] when it
  /// can't be read.
  Future<RommRights> rights() async {
    try {
      final r = await _dio.get<dynamic>('/api/permissions/me', options: _adminOptions);
      if (r.statusCode == 200 && r.data is Map) return RommRights.fromPermissions(r.data as Map);
      if (r.statusCode != 404) {
        debugPrint('[RomM] permissions not read: ${r.statusCode}');
        return RommRights.none;
      }
    } catch (e) {
      debugPrint('[RomM] permissions not read: $e');
      return RommRights.none;
    }
    try {
      final data = (await _dio.get<dynamic>('/api/users/me', options: _authOptions)).data;
      return RommRights.fromRole(data is Map ? data['role'] : null);
    } catch (e) {
      debugPrint('[RomM] role not read: $e');
      return RommRights.none;
    }
  }

  /// Gargosy: whether the user may delete games on RomM: RomM 5.4's
  /// `/api/permissions/me` (an admin, or the `rom.delete` action), else on an
  /// older RomM an admin's or editor's role. False when RomM can't say.
  Future<bool> canDeleteGames() async => (await rights()).deleteGames;

  /// Starts a scan of the library, or of [platformIds] only
  /// (`POST /api/tasks/scan`, RomM 5.4). Gives the task's id to follow with
  /// [scanProgress]. Throws [RommAdminRefused] with why RomM said no.
  Future<String> startScan(ScanKind kind, {List<int> platformIds = const []}) async {
    final r = await _dio.post<dynamic>(
      '/api/tasks/scan',
      data: {'type': kind.wire, if (platformIds.isNotEmpty) 'platforms': platformIds},
      options: _adminOptions.copyWith(contentType: Headers.jsonContentType),
    );
    _refusedUnlessOk(r, tr('RomM didn\'t start the scan'));
    final id = r.data is Map ? r.data['task_id'] : null;
    if (id is! String || id.isEmpty) throw RommAdminRefused(r.statusCode ?? 0, tr('RomM didn\'t start the scan'));
    return id;
  }

  /// Where scan [taskId] is (`GET /api/tasks/{id}`).
  Future<ScanProgress> scanProgress(String taskId) async {
    final r = await _dio.get<dynamic>('/api/tasks/${Uri.encodeComponent(taskId)}', options: _adminOptions);
    _refusedUnlessOk(r, tr('RomM lost the scan'));
    if (r.data is! Map) throw RommAdminRefused(r.statusCode ?? 0, tr('RomM lost the scan'));
    return ScanProgress.fromJson(r.data as Map);
  }

  /// Uploads the file at [path] to platform [platformId]'s folder on RomM
  /// (`/api/roms/upload/start`, a `PUT` per piece, `/complete`), as RomM's
  /// web UI does. [onProgress] hears the bytes sent. A failure or [cancel]
  /// cancels the upload on RomM, so nothing half-sent stays; then throws
  /// ([RommAdminRefused] with RomM's reason, or the error). RomM adds the
  /// game once it scans the platform.
  Future<void> uploadGame(
    int platformId,
    String path, {
    void Function(int sent, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final file = io.File(path);
    final size = await file.length();
    final name = p.basename(path);
    final chunks = (size / uploadChunkBytes).ceil();
    final start = await _dio.post<dynamic>(
      '/api/roms/upload/start',
      // The header can't hold a name outside Latin-1: the body has the real one.
      data: {'filename': name},
      options: _adminOptions.copyWith(
        contentType: Headers.jsonContentType,
        headers: {
          'X-Upload-Platform': '$platformId',
          'X-Upload-Filename': Uri.encodeComponent(name),
          'X-Upload-Total-Size': '$size',
          'X-Upload-Total-Chunks': '$chunks',
        },
      ),
      cancelToken: cancel,
    );
    _refusedUnlessOk(start, tr('RomM didn\'t take the upload'));
    final id = start.data is Map ? start.data['upload_id'] : null;
    if (id is! String || id.isEmpty) throw RommAdminRefused(start.statusCode ?? 0, tr('RomM didn\'t take the upload'));
    final at = '/api/roms/upload/${Uri.encodeComponent(id)}';
    final raf = await file.open();
    try {
      var sent = 0;
      onProgress?.call(0, size);
      for (var i = 0; i < chunks; i++) {
        final bytes = await raf.read(uploadChunkBytes);
        Response<dynamic>? r;
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            r = await _dio.put<dynamic>(
              at,
              data: Stream<List<int>>.value(bytes),
              options: _adminOptions.copyWith(
                contentType: 'application/octet-stream',
                sendTimeout: const Duration(minutes: 2),
                headers: {'X-Chunk-Index': '$i', Headers.contentLengthHeader: bytes.length},
              ),
              cancelToken: cancel,
            );
            if ((r.statusCode ?? 0) < 500) break;
          } on DioException catch (e) {
            if (CancelToken.isCancel(e) || attempt == 2) rethrow;
          }
        }
        _refusedUnlessOk(r!, tr('RomM didn\'t take the upload'));
        sent += bytes.length;
        onProgress?.call(sent, size);
      }
      final done = await _dio.post<dynamic>('$at/complete', options: _adminOptions, cancelToken: cancel);
      _refusedUnlessOk(done, tr('RomM didn\'t take the upload'));
    } catch (_) {
      try {
        await _dio.post<dynamic>('$at/cancel', options: _adminOptions);
      } catch (e) {
        debugPrint('[RomM] upload $id not cancelled: $e');
      }
      rethrow;
    } finally {
      await raf.close();
    }
  }

  /// The games the metadata sources know by [term] (the game's file name
  /// when null), for game [romId] (`GET /api/search/roms`).
  Future<List<MatchCandidate>> searchMatches(String romId, {String? term}) async {
    final r = await _dio.get<dynamic>(
      '/api/search/roms',
      queryParameters: {'rom_id': romId, 'search_by': 'name', if (term != null && term.isNotEmpty) 'search_term': term},
      options: _adminOptions.copyWith(receiveTimeout: const Duration(minutes: 2)),
    );
    _refusedUnlessOk(r, tr('RomM couldn\'t search'));
    final data = r.data;
    return [
      if (data is List)
        for (final item in data) ?MatchCandidate.fromJson(item),
    ];
  }

  /// Makes [match] game [romId]'s metadata (`PUT /api/roms/{id}`): every
  /// source's id (one it lacks cleared), its name, summary and cover; RomM
  /// fetches the rest from the sources. The file's name stays.
  Future<void> applyMatch(String romId, MatchCandidate match) async {
    final r = await _dio.put<dynamic>(
      '/api/roms/${Uri.encodeComponent(romId)}',
      data: FormData.fromMap({
        for (final f in MatchCandidate.matchFields) f: match.ids[f] ?? '',
        'name': match.name,
        'summary': match.summary,
        'url_cover': match.coverForGame,
      }),
      options: _adminOptions.copyWith(
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    _refusedUnlessOk(r, tr('RomM didn\'t change the match'));
  }

  /// Throws [RommAdminRefused] unless [r] is a 2xx: RomM's `detail` when it
  /// gave one, else what the status means.
  void _refusedUnlessOk(Response<dynamic> r, String what) {
    final status = r.statusCode ?? 0;
    if (status >= 200 && status < 300) return;
    final detail = r.data is Map ? r.data['detail'] : null;
    final why = switch (status) {
      403 => tr('This login may not do that. An admin may need to sign in again (Settings → Profile → RomM account).'),
      404 when detail == null => tr('This RomM is too old for it (5.4 or newer).'),
      _ when detail is String && detail.isNotEmpty => detail,
      _ => tr('RomM answered {0}', [status]),
    };
    throw RommAdminRefused(status, '$what: $why');
  }
}
