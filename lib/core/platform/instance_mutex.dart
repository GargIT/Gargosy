import 'dart:convert';
import 'dart:ffi';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// #223 (hand test 126): one Gargosy per folder on Windows is a named mutex,
/// not a file lock: in the running app the lock on `instance.lock` was let
/// go within seconds of starting (a second start then found no Gargosy and
/// opened another window), which no plain Dart process reproduced. A mutex
/// is Windows' own way: it goes only when its handle is closed or the
/// process ends, a crash included.
class InstanceMutex {
  InstanceMutex._(this._handle);

  final int _handle;

  /// The mutex's name for the Gargosy folder [root]: for every Windows
  /// session (`Global\`, so another user signed in on the PC finds it too),
  /// the folder as Windows resolves it (a junction, a `subst` drive) made
  /// one case and hashed.
  static String nameFor(String root) => 'Global\\Gargosy-${sha1.convert(utf8.encode(_resolved(root).toLowerCase()))}';

  static String _resolved(String root) {
    final path = p.normalize(p.absolute(root));
    try {
      return p.normalize(io.Directory(path).resolveSymbolicLinksSync());
    } on io.FileSystemException {
      return path;
    }
  }

  /// The mutex for [root], or null when another process holds it (one this
  /// process may not open, another user's or an elevated one's, included).
  static InstanceMutex? claim(String root) {
    // GetLastError resolved before the call it reads after, so Dart's
    // runtime doesn't clobber it in between (as win32 does).
    GetLastError();
    final name = nameFor(root).toNativeUtf16();
    try {
      final handle = _createMutex(nullptr, 0, name);
      final error = GetLastError();
      if (handle == 0) {
        if (error == ERROR_ACCESS_DENIED) return null;
        throw WindowsException(error, message: 'CreateMutexW failed');
      }
      if (error == ERROR_ALREADY_EXISTS) {
        CloseHandle(handle);
        return null;
      }
      return InstanceMutex._(handle);
    } finally {
      calloc.free(name);
    }
  }

  /// Lets the folder go (tests; the process's end lets it go by itself).
  void release() => CloseHandle(_handle);
}

final _createMutex = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<IntPtr Function(Pointer, Int32, Pointer<Utf16>), int Function(Pointer, int, Pointer<Utf16>)>(
      'CreateMutexW',
      isLeaf: true,
    );
