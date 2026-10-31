import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../profiles/app_root.dart';
import '../../profiles/json_file.dart';
import '../../profiles/path_guard.dart';
import 'instance_mutex.dart';
import 'platform_info.dart';

/// #223: one Gargosy per Gargosy folder. The first start holds the folder
/// (on Windows a named mutex, [InstanceMutex]; elsewhere
/// `userdata\app\instance.lock`) and listens on a loopback port (in
/// `instance.json`, with a token); a second start (a shortcut's `--play`,
/// Steam) hands its arguments to it and exits, so two never run emulators
/// on the same profiles. The hold goes with the process, also after a crash.
class AppInstance {
  AppInstance._(this._letGo, this._server, this._requests) {
    // Held for the process's life: nothing is collected while it runs.
    _held = this;
  }

  /// The claim this process holds.
  static AppInstance? _held;

  @visibleForTesting
  static AppInstance? get held => _held;

  /// A start that holds nothing: the holder couldn't be reached, so this one
  /// runs rather than end without a word.
  AppInstance._unclaimed() : _letGo = null, _server = null, _requests = StreamController<List<String>>();

  /// Lets the folder go: the mutex's or the lock file's.
  final Future<void> Function()? _letGo;
  final io.ServerSocket? _server;

  /// Single-subscription, so what a later start sends before Gargosy listens
  /// (while it is still starting) waits for it.
  final StreamController<List<String>> _requests;

  /// The arguments of each later start, as it was given them; listened to once.
  Stream<List<String>> get requests => _requests.stream;

  /// Whether this start holds the folder.
  bool get holds => _letGo != null;

  static String lockPath(AppRoot root) => p.join(root.appData, 'instance.lock');
  static String infoPath(AppRoot root) => p.join(root.appData, 'instance.json');

  /// How long a later start may take to send its arguments.
  static const readTimeout = Duration(seconds: 5);

  /// This start's claim on [root], or null when another Gargosy holds it and
  /// took [args]: this one should exit. When the holder can't be reached, a
  /// claim that holds nothing, and Gargosy starts. A claim that fails half
  /// way lets the lock go before it throws.
  static Future<AppInstance?> claim(AppRoot root, List<String> args, {PlatformInfo? platform}) async {
    final guard = PathGuard(root);
    final Future<void> Function() letGo;
    if ((platform ?? PlatformInfo.current).isWindows) {
      final mutex = InstanceMutex.claim(root.root);
      if (mutex == null) {
        if (await handOver(root, args)) return null;
        return AppInstance._unclaimed();
      }
      letGo = () async => mutex.release();
    } else {
      final lock = await io.File(guard.check(lockPath(root))).open(mode: io.FileMode.append);
      try {
        await lock.lock(io.FileLock.exclusive);
      } on io.FileSystemException {
        await lock.close();
        if (await handOver(root, args)) return null;
        return AppInstance._unclaimed();
      }
      letGo = () async {
        await lock.unlock();
        await lock.close();
      };
    }
    io.ServerSocket? server;
    try {
      // A crashed holder's port is never read while this one starts.
      final info = io.File(guard.check(infoPath(root)));
      if (info.existsSync()) info.deleteSync();
      server = await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0);
      final token = _token();
      await writeJsonObject(guard, infoPath(root), {'port': server.port, 'token': token, 'pid': io.pid});
      final requests = StreamController<List<String>>();
      server.listen((socket) => _read(socket, token, requests));
      return AppInstance._(letGo, server, requests);
    } on Object {
      await server?.close();
      await letGo();
      rethrow;
    }
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
    debugPrint('[Instance] another Gargosy holds the folder but could not be reached; starting anyway');
    return false;
  }

  /// One line of JSON from a later start, read until its newline (or the
  /// connection ends) within [readTimeout]; anything else (no token, too
  /// long, too slow) is dropped.
  static void _read(io.Socket socket, String token, StreamController<List<String>> into) {
    final buf = <int>[];
    var done = false;
    late final Timer timer;
    void finish() {
      if (done) return;
      done = true;
      timer.cancel();
      socket.destroy();
      try {
        final msg = jsonDecode(utf8.decode(buf, allowMalformed: true).trim());
        if (msg is Map && msg['token'] == token && msg['args'] is List) {
          into.add([for (final a in msg['args'] as List) '$a']);
        }
      } on FormatException {
        return;
      }
    }

    timer = Timer(readTimeout, () {
      done = true;
      socket.destroy();
    });
    socket.listen(
      (data) {
        if (done) return;
        buf.addAll(data);
        if (buf.length > 64 * 1024) {
          done = true;
          timer.cancel();
          socket.destroy();
        } else if (data.contains(10)) {
          finish();
        }
      },
      onDone: finish,
      onError: (Object _) {
        done = true;
        timer.cancel();
        socket.destroy();
      },
      cancelOnError: true,
    );
  }

  static String _token() {
    final r = Random.secure();
    return [for (var i = 0; i < 16; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }

  /// Lets the folder go (tests; a normal exit lets it go by itself).
  Future<void> release() async {
    if (identical(_held, this)) _held = null;
    await _server?.close();
    // Never listened, a single-subscription stream's close never completes.
    unawaited(_requests.close());
    await _letGo?.call();
  }
}
