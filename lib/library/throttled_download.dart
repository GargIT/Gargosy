import 'dart:io' as io;

import 'package:dio/dio.dart';

/// #228: [url] into [path] at no more than [bytesPerSecond] (read again for
/// each chunk, so a changed limit applies at once; 0 is no limit), the
/// response streamed and written chunk by chunk. A failure or cancel
/// deletes what was written, as `Dio.download(deleteOnError: true)` does.
Future<void> downloadThrottled(
  Dio dio,
  String url,
  String path, {
  required Options options,
  required int Function() bytesPerSecond,
  CancelToken? cancel,
  void Function(int received, int total)? onProgress,
  Stopwatch? clock,
  Future<void> Function(Duration) sleep = Future<void>.delayed,
}) async {
  final watch = clock ?? (Stopwatch()..start());
  final file = io.File(path);
  final sink = file.openWrite();
  try {
    final r = await dio.get<ResponseBody>(
      url,
      options: options.copyWith(responseType: ResponseType.stream),
      cancelToken: cancel,
    );
    final total = int.tryParse(r.headers.value(Headers.contentLengthHeader) ?? '') ?? -1;
    var received = 0;
    await for (final chunk in r.data!.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
      final rate = bytesPerSecond();
      if (rate <= 0) continue;
      // Ahead of the limit: wait until the bytes so far are due.
      final due = Duration(microseconds: received * 1000000 ~/ rate);
      final ahead = due - watch.elapsed;
      if (ahead > Duration.zero) await sleep(ahead);
      if (cancel?.isCancelled ?? false) {
        throw DioException.requestCancelled(requestOptions: r.requestOptions, reason: cancel!.cancelError?.message);
      }
    }
    await sink.close();
  } on Object {
    await sink.close().catchError((Object _) {});
    if (file.existsSync()) file.deleteSync();
    rethrow;
  }
}
