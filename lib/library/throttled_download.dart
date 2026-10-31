import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// #228: [inner] with responses paced to [bytesPerSecond] (read again for
/// each chunk, so a changed limit applies to a running download; 0 is no
/// limit). Paced where the bytes come off the socket: while it waits, the
/// `await for` keeps the socket's subscription paused, so the line really
/// slows and nothing piles up in memory (dio's own response stream passes
/// no pause back).
class ThrottledAdapter implements HttpClientAdapter {
  ThrottledAdapter(this.inner, this.bytesPerSecond, {Stopwatch Function()? clock, this.sleep = Future<void>.delayed})
    : _clock = clock ?? (() => Stopwatch()..start());

  final HttpClientAdapter inner;
  final int Function() bytesPerSecond;
  final Stopwatch Function() _clock;

  /// Waits; tests replace it.
  final Future<void> Function(Duration) sleep;

  /// The longest single wait: a cancel or a raised limit is heard within it.
  static const maxWait = Duration(milliseconds: 500);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = await inner.fetch(options, requestStream, cancelFuture);
    return ResponseBody(
      paced(body.stream),
      body.statusCode,
      headers: body.headers,
      statusMessage: body.statusMessage,
      isRedirect: body.isRedirect,
      redirects: body.redirects,
    );
  }

  /// [source] no faster than [bytesPerSecond], measured from when the limit
  /// was last set: a lowered limit doesn't freeze for what came before it,
  /// a raised one doesn't burst to catch up.
  Stream<Uint8List> paced(Stream<Uint8List> source) async* {
    var rate = 0;
    var since = _clock();
    var sent = 0;
    await for (final chunk in source) {
      final now = bytesPerSecond();
      if (now != rate) {
        rate = now;
        since = _clock();
        sent = 0;
      }
      sent += chunk.length;
      if (rate > 0) {
        var ahead = Duration(microseconds: sent * 1000000 ~/ rate) - since.elapsed;
        while (ahead > Duration.zero) {
          final wait = ahead > maxWait ? maxWait : ahead;
          await sleep(wait);
          ahead -= wait;
          // A changed limit is heard here, not after the whole wait.
          if (bytesPerSecond() != rate) break;
        }
      }
      yield chunk;
    }
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// A copy of [base] (its options, transformer and interceptors) whose
/// responses [ThrottledAdapter] paces; for downloads.
Dio throttledDio(Dio base, int Function() bytesPerSecond) {
  final dio = Dio(base.options)
    ..httpClientAdapter = ThrottledAdapter(base.httpClientAdapter, bytesPerSecond)
    ..transformer = base.transformer;
  // Dio's own content-type step comes twice; it only fills in what's missing.
  dio.interceptors.addAll(base.interceptors);
  return dio;
}
