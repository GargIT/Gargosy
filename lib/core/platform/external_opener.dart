import 'dart:io' as io;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import 'platform_info.dart';

/// Opens a web address, a folder or a file with the system's default
/// program.
typedef ExternalOpener = void Function(String target);

/// [platform]'s way to open something outside Gargosy.
ExternalOpener externalOpenerFor(PlatformInfo platform) {
  if (platform.isWindows) return shellOpen;
  final program = platform.isMacOS ? 'open' : 'xdg-open';
  return (target) => io.Process.start(program, [target]);
}

/// Windows' "open" on [target] (#231): the shell picks the browser for an
/// address and Explorer for a folder, and nothing in it (&, %, |) is read as
/// a command. `explorer.exe <address>` opened the Documents folder instead
/// of a GitHub address with a query.
void shellOpen(String target) {
  using((arena) {
    final result = ShellExecute(
      null,
      PCWSTR('open'.toNativeUtf16(allocator: arena)),
      PCWSTR(target.toNativeUtf16(allocator: arena)),
      null,
      null,
      SW_SHOWNORMAL,
    );
    // Above 32 is success (ShellExecute's own rule).
    if (result.address <= 32) debugPrint('[Open] Windows could not open $target (${result.address})');
  });
}
