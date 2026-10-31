import 'dart:io' as io;
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import 'platform_info.dart';

/// Opens a web address or a folder with the system's default program;
/// false when it didn't (refused, or the system couldn't).
typedef ExternalOpener = Future<bool> Function(String target);

/// [platform]'s way to open something outside Gargosy.
ExternalOpener externalOpenerFor(PlatformInfo platform) {
  if (platform.isWindows) return (target) => _checked(target, shellOpen);
  final program = platform.isMacOS ? 'open' : 'xdg-open';
  return (target) => _checked(target, (t) async {
    try {
      await io.Process.start(program, [t], mode: io.ProcessStartMode.detached);
      return true;
    } on io.ProcessException catch (e) {
      debugPrint('[Open] $program: $e');
      return false;
    }
  });
}

/// What may be opened outside: an http(s) address or a folder that is
/// there. Anything else (a program, a script, another scheme's handler) is
/// refused, whatever a document's link or a server says.
bool mayOpenOutside(String target) {
  final uri = Uri.tryParse(target);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) return uri.host.isNotEmpty;
  try {
    return io.Directory(target).existsSync();
  } on io.FileSystemException {
    return false; // not a path at all (`file:///…`, `ms-settings:`)
  }
}

Future<bool> _checked(String target, Future<bool> Function(String) open) async {
  if (!mayOpenOutside(target)) {
    debugPrint('[Open] refused: $target');
    return false;
  }
  return open(target);
}

/// Windows' default verb on [target] (#231), as a double-click: the browser
/// for an address, Explorer for a folder; nothing in it (&, %, |) is read as
/// a command. `explorer.exe <address>` opened the Documents folder instead
/// of a GitHub address with a query. Off the UI thread: the shell may wait
/// on a browser starting or a sleeping network drive.
Future<bool> shellOpen(String target) async {
  final result = await Isolate.run(() {
    CoInitializeEx(COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    try {
      return using(
        (arena) =>
            ShellExecute(null, null, PCWSTR(target.toNativeUtf16(allocator: arena)), null, null, SW_SHOWNORMAL).address,
      );
    } finally {
      CoUninitialize();
    }
  });
  // Above 32 is success (ShellExecute's own rule).
  if (result > 32) return true;
  debugPrint('[Open] Windows could not open $target ($result)');
  return false;
}
