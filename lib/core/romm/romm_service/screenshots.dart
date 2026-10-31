part of '../romm_service.dart';

/// Screenshots taken in a game, sent to RomM (#233).
mixin _RommScreenshots on _RommBase {
  /// Sends the image at [path] as one of [romId]'s screenshots
  /// (`POST /api/screenshots`, RomM 5.4: the player's own, private until
  /// shared). Throws when RomM doesn't take it; [ScreenshotRefused] when it
  /// never will (an older RomM, a game gone, a file it refuses).
  Future<void> uploadScreenshot(String romId, String path) async {
    try {
      await _dio.post<dynamic>(
        '/api/screenshots',
        queryParameters: {'rom_id': romId},
        data: FormData.fromMap({'screenshotFile': await MultipartFile.fromFile(path, filename: p.basename(path))}),
        options: _authOptions.copyWith(sendTimeout: const Duration(minutes: 2)),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status != null && status >= 400 && status < 500 && status != 401 && status != 408 && status != 429) {
        throw ScreenshotRefused(status);
      }
      rethrow;
    }
  }

  /// One of the player's screenshots by its `download_path` (private on
  /// RomM, so asked with the token, not through the image cache). Throws
  /// when RomM can't give it.
  Future<Uint8List> screenshotBytes(String downloadPath) async {
    final r = await _dio.get<List<int>>(downloadPath, options: _authOptions.copyWith(responseType: ResponseType.bytes));
    final data = r.data;
    if (data == null || data.isEmpty) throw StateError('RomM sent no screenshot');
    return data is Uint8List ? data : Uint8List.fromList(data);
  }
}

/// RomM answered a screenshot with a client error: trying again won't help.
class ScreenshotRefused implements Exception {
  const ScreenshotRefused(this.status);
  final int status;
  @override
  String toString() => 'RomM refused the screenshot ($status)';
}
