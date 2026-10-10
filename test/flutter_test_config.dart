import 'dart:async';
import 'dart:io' as io;

import 'package:gargosy/sigil/sigil_library.dart';
import 'package:path/path.dart' as p;

/// Points every test at a built sigil.dll: tool/build_sigil.ps1's, else the
/// Windows build's. None found: SigilLibrary.open names where it looked
/// (run `powershell -File tool/build_sigil.ps1` once).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  const candidates = [
    'build/sigil/Release/sigil.dll',
    'build/windows/x64/runner/Release/sigil.dll',
    'build/windows/x64/runner/Debug/sigil.dll',
  ];
  SigilLibrary.path = candidates
      .map(p.absolute)
      .firstWhere((c) => io.File(c).existsSync(), orElse: () => p.absolute(candidates.first));
  await testMain();
}
