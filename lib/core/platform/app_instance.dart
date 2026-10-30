import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../profiles/app_root.dart';
import '../../profiles/json_file.dart';
import '../../profiles/path_guard.dart';

/// #223: one Gargosy per Gargosy folder. The first start holds
/// `userdata\app\instance.lock` and listens on a loopback port (in
/// `instance.json`, with a token); a second start (a shortcut's `--play`,
/// Steam) hands its arguments to it and exits, so two never run emulators
/// on the same profiles. The lock goes with the process, also after a crash.
class AppInstance {
  AppInstance._(this._lock, this._server, this._requests);

  final io.RandomAccessFile _lock;
  final io.ServerSocket _server;
  final StreamController<List<String>> _requests;

  /// The arguments of each later start, as it was given them.
  Stream<List<String>> get requests => _requests.stream;

  static String lockPath(AppRoot root) => p.join(root.appData, 'instance.lock');
  static String infoPath(AppRoot root) => p.join(root.appData, 'instance.json');

  /// This start's claim on [root], or null when another Gargosy holds it and
  /// took [args] (or couldn't be reached): this one should exit.
  static Future<AppInstance?> claim(AppRoot root, List<String> args) async {
    final guard = PathGuard(root);
    final lock = await io.File(guard.check(lockPath(root))).open(mode: io.FileMode.append);
    try {
      await lock.lock(io.FileLock.exclusive);
    } on io.FileSystemException {
      await lock.close();
      await handOver(root, args);
      return null;
    }
    final server = await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0);
    final token = _token();
    await writeJsonObject(guard, infoPath(root), {'port': server.port, 'token': token, 'pid': io.pid});
    final requests = StreamController<List<String>>.broadcast();
    server.listen((socket) => _read(socket, token, requests));
    return AppInstance._(lock, server, requests);
  }

  /// Sends [args] to the Gargosy holding [root], trying for a few seconds
  /// (it may still be starting). False when it couldn't be reached.
  @visibleForTesting
  static Future<bool> handOver(AppRoot root, List<String> args, {int tries = 15}) async {
    for (var i = 0; i < tries; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 200));
      final info = await readJsonObject(infoPath(root));
      final port = info?['port'], token = info?['token'];
      if (port is! int || token is! String) continue;
      try {
        final s = await io.Socket.connect(io.InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1));
        s.write('${jsonEncode({'token': token, 'args': args})}\n');
        await s.flush();
        await s.close();
        debugPrint('[Instance] handed $args to the Gargosy already running');
        return true;
      } on io.SocketException {
        continue;
      }
    }
    debugPrint('[Instance] another Gargosy holds the folder but could not be reached');
    return false;
  }

  /// One line of JSON from a later start; anything else (no token, too long)
  /// is dropped.
  static void _read(io.Socket socket, String token, StreamController<List<String>> into) {
    final buf = <int>[];
    socket.listen(
      (data) {
        buf.addAll(data);
        if (buf.length > 64 * 1024) socket.destroy();
      },
      onDone: () {
        socket.destroy();
        try {
          final msg = jsonDecode(utf8.decode(buf).trim());
          if (msg is Map && msg['token'] == token && msg['args'] is List) {
            into.add([for (final a in msg['args'] as List) '$a']);
          }
        } on FormatException {
          return;
        }
      },
      onError: (Object _) => socket.destroy(),
      cancelOnError: true,
    );
  }

  static String _token() {
    final r = Random.secure();
    return [for (var i = 0; i < 16; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }

  /// Lets the folder go (tests; a normal exit lets it go by itself).
  Future<void> release() async {
    await _server.close();
    await _requests.close();
    await _lock.unlock();
    await _lock.close();
  }
}
