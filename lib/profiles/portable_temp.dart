import 'dart:io' as io;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Points this process's temp folder (TMP and TEMP, which Windows'
/// GetTempPath and so Dart's Directory.systemTemp read) at [dir] inside the
/// Gargosy folder. Freegosy's save code makes its working copies of saves
/// in the temp folder; with this they never land in the user's AppData
/// (spec §3: nothing in AppData), and emulators started from here inherit
/// it too.
void usePortableTemp(String dir) {
  io.Directory(dir).createSync(recursive: true);
  for (final name in const ['TMP', 'TEMP']) {
    final n = name.toNativeUtf16();
    final v = dir.toNativeUtf16();
    try {
      SetEnvironmentVariable(PCWSTR(n), PCWSTR(v));
    } finally {
      calloc.free(n);
      calloc.free(v);
    }
  }
}
