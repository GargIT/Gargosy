import 'dart:convert';
import 'dart:ffi';

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

  /// This process's mutex, held until it ends: never collected or closed.
  static InstanceMutex? _held;

  /// The mutex's name for the Gargosy folder [root]: per Windows session
  /// (`Local\`), its path made one case and hashed.
  static String nameFor(String root) =>
      'Local\\Gargosy-${sha1.convert(utf8.encode(p.normalize(p.absolute(root)).toLowerCase()))}';

  /// The mutex for [root], or null when another process holds it.
  static InstanceMutex? claim(String root) {
    // GetLastError resolved before the call it reads after, so Dart's
    // runtime doesn't clobber it in between (as win32 does).
    GetLastError();
    final name = nameFor(root).toNativeUtf16();
    try {
      final handle = _createMutex(nullptr, 0, name);
      final error = GetLastError();
      if (handle == 0) throw WindowsException(error.toHRESULT(), message: 'CreateMutexW failed');
      if (error == ERROR_ALREADY_EXISTS) {
        CloseHandle(HANDLE(Pointer.fromAddress(handle)));
        return null;
      }
      return _held = InstanceMutex._(handle);
    } finally {
      calloc.free(name);
    }
  }

  /// Lets the folder go (tests; the process's end lets it go by itself).
  void release() {
    if (identical(_held, this)) _held = null;
    CloseHandle(HANDLE(Pointer.fromAddress(_handle)));
  }
}

final _createMutex = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<IntPtr Function(Pointer, Int32, Pointer<Utf16>), int Function(Pointer, int, Pointer<Utf16>)>(
      'CreateMutexW',
      isLeaf: true,
    );
