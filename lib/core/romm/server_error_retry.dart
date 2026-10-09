import 'package:dio/dio.dart';

/// Asks RomM again when a read (GET) fails with a server error (5xx): Home
/// sends several requests at once on start, and RomM now and then answers
/// one with a 500 that a moment later works. Changes (POST, PUT, DELETE…)
/// are never repeated.
class ServerErrorRetry extends Interceptor {
  ServerErrorRetry(this._dio, {this.delays = const [Duration(milliseconds: 400), Duration(milliseconds: 800)]});

  final Dio _dio;

  /// The pause before each retry; as many retries as pauses.
  final List<Duration> delays;

  static const _attemptKey = 'gargosy_retry_attempt';

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final r = err.requestOptions;
    final status = err.response?.statusCode ?? 0;
    final attempt = (r.extra[_attemptKey] as int?) ?? 0;
    if (r.method.toUpperCase() != 'GET' || status < 500 || status > 599 || attempt >= delays.length) {
      return handler.next(err);
    }
    await Future<void>.delayed(delays[attempt]);
    try {
      final again = r.copyWith(extra: {...r.extra, _attemptKey: attempt + 1});
      handler.resolve(await _dio.fetch<dynamic>(again));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
