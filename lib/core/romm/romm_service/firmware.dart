// Adapted from Freegosy (MIT, © 2026 abduznik).
part of '../romm_service.dart';

/// Firmware (`/api/firmware`).
mixin _RommFirmware on _RommBase {
  Future<List<Firmware>> getFirmware({String? platformId}) async {
    final params = platformId != null ? {'platform_id': platformId} : <String, dynamic>{};
    final response = await _dio.get('/api/firmware', queryParameters: params, options: _authOptions);
    if (response.statusCode == 200) {
      final List<dynamic> items = (response.data is Map && response.data.containsKey('items'))
          ? response.data['items']
          : response.data as List<dynamic>;
      return items.map((item) => Firmware.fromJson(item)).toList();
    }
    throw DioException(requestOptions: response.requestOptions, response: response, type: DioExceptionType.badResponse);
  }

  String getFirmwareDownloadUrl(Firmware firmware) {
    final baseUrl = _normalizeBaseUrl(_config.baseUrl);
    return '$baseUrl/api/firmware/${firmware.id}/content/${Uri.encodeComponent(firmware.fileName)}';
  }

  Future<Uint8List?> downloadFirmware(Firmware firmware, {void Function(int received, int total)? onProgress}) async {
    try {
      final url = getFirmwareDownloadUrl(firmware);
      final response = await _dio.get<List<int>>(
        url,
        options: _authOptions.copyWith(responseType: ResponseType.bytes),
        onReceiveProgress: onProgress,
      );
      return (response.statusCode == 200 && response.data != null) ? Uint8List.fromList(response.data!) : null;
    } catch (_) {
      return null;
    }
  }
}
