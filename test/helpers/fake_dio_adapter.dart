import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef FakeReply = ({int status, Object? body});

/// A Dio adapter that answers from [handler] and records every request.
class FakeDioAdapter implements HttpClientAdapter {
  FakeDioAdapter(this.handler);

  final FakeReply Function(RequestOptions request) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final reply = handler(options);
    if (reply.status == -1) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final body = reply.body;
    if (body is List<int>) {
      return ResponseBody.fromBytes(body, reply.status, headers: {
        Headers.contentTypeHeader: ['image/png'],
      });
    }
    return ResponseBody.fromString(jsonEncode(body), reply.status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// A Dio for [baseUrl] that answers through [adapter].
Dio fakeDio(FakeDioAdapter adapter, {String baseUrl = 'https://romm.example'}) =>
    Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = adapter;
