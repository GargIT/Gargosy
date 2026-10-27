// Adapted from Freegosy (MIT, © 2026 abduznik).
part of '../romm_service.dart';

/// Save states (`/api/states`).
mixin _RommStates on _RommBase implements RommStatesApi {
  /// Gargosy (#94): deletes the player's own states on RomM
  /// (`POST /api/states/delete`). Whether RomM took it.
  Future<bool> deleteStates(List<int> stateIds) async {
    if (stateIds.isEmpty) return true;
    try {
      final response = await _dio.post(
        '/api/states/delete',
        data: {'states': stateIds},
        options: _authOptions.copyWith(contentType: 'application/json'),
      );
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (e) {
      debugPrint('[RomM] deleteStates error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Save states (/api/states) — per RomM user, private by default
  // ---------------------------------------------------------------------------

  Options get _stateOptions =>
      _authOptions.copyWith(sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 5));

  /// Options for [downloadState]: the short inactivity bound, and no retries
  /// (the sync stops at the first failed download instead).
  Options get _stateDownloadOptions => _authOptions.copyWith(
    responseType: ResponseType.bytes,
    receiveTimeout: RommService.stateDownloadInactivityTimeout,
    extra: {'no_retry': true},
  );

  @override
  Future<List<RommState>> listStates(String romId) async {
    final response = await _dio.get('/api/states', queryParameters: {'rom_id': romId}, options: _authOptions);
    final data = response.data;
    final List<dynamic> items = data is Map
        ? (data['items'] as List<dynamic>? ?? const [])
        : (data as List<dynamic>? ?? const []);
    return items.whereType<Map<String, dynamic>>().map(RommState.fromJson).toList();
  }

  Map<String, dynamic> _stateForm(MultipartFile state, String fileName, Uint8List? screenshot) => {
    'stateFile': state,
    if (screenshot != null) 'screenshotFile': MultipartFile.fromBytes(screenshot, filename: '$fileName.png'),
  };

  @override
  Future<RommState> uploadState(
    String romId,
    io.File file, {
    required String fileName,
    String? emulator,
    Uint8List? screenshot,
  }) async {
    final response = await _dio.post(
      '/api/states',
      queryParameters: {'rom_id': romId, 'emulator': ?emulator},
      data: FormData.fromMap(
        _stateForm(await MultipartFile.fromFile(file.path, filename: fileName), fileName, screenshot),
      ),
      options: _stateOptions,
    );
    return RommState.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<RommState> updateState(int stateId, io.File file, {required String fileName, Uint8List? screenshot}) async {
    try {
      final response = await _dio.put(
        '/api/states/$stateId',
        data: FormData.fromMap(
          _stateForm(await MultipartFile.fromFile(file.path, filename: fileName), fileName, screenshot),
        ),
        options: _stateOptions,
      );
      return RommState.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw RommStateNotFoundException(stateId);
      rethrow;
    }
  }

  @override
  Future<RommState> setStateLabels(int stateId, List<String> labels) async {
    final response = await _dio.put('/api/states/$stateId/labels', data: {'labels': labels}, options: _authOptions);
    return RommState.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<Uint8List> downloadState(int stateId) async {
    try {
      final response = await _dio.get<List<int>>('/api/states/$stateId/content', options: _stateDownloadOptions);
      return Uint8List.fromList(List<int>.from(response.data ?? const <int>[]));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw RommStateNotFoundException(stateId);
      rethrow;
    }
  }

  @override
  Future<Uint8List> downloadStateScreenshot(String url) async {
    final uri = Uri.parse(url);
    if (!url.startsWith('/') || uri.hasScheme || uri.hasAuthority) {
      throw ArgumentError.value(url, 'url', 'must be a server-relative path');
    }
    final response = await _dio.get<List<int>>(url, options: _stateDownloadOptions);
    return Uint8List.fromList(List<int>.from(response.data ?? const <int>[]));
  }
}
