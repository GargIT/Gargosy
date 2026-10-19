import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One answer from the fake GitHub: a status, a JSON body and headers, or
/// [offline] for a connection error.
class GitHubReply {
  const GitHubReply(this.status, [this.body, this.headers = const {}]) : offline = false;
  const GitHubReply.offline() : status = 0, body = null, headers = const {}, offline = true;

  final int status;
  final Object? body;
  final Map<String, String> headers;
  final bool offline;
}

/// A Dio adapter that answers as GitHub's API would, with headers (ETag),
/// and records every request.
class FakeGitHub implements HttpClientAdapter {
  FakeGitHub(this.handler);

  GitHubReply Function(RequestOptions request) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = handler(options);
    if (reply.offline) throw DioException.connectionError(requestOptions: options, reason: 'offline');
    final body = reply.body;
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final h in reply.headers.entries) h.key: [h.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A GitHub release as the API describes it, with a `Gargosy-<version>.zip`.
Map<String, Object?> githubRelease(
  String version, {
  bool prerelease = false,
  bool draft = false,
  String? tag,
  String? digest,
  int size = 1000,
  String body = 'Notes',
}) => {
  'tag_name': tag ?? 'v$version',
  'html_url': 'https://github.com/GargIT/Gargosy/releases/tag/${tag ?? 'v$version'}',
  'prerelease': prerelease,
  'draft': draft,
  'body': body,
  'assets': [
    {
      'name': 'Gargosy-$version.zip',
      'size': size,
      'browser_download_url':
          'https://github.com/GargIT/Gargosy/releases/download/${tag ?? 'v$version'}/Gargosy-$version.zip',
      'digest': ?digest,
    },
  ],
};
