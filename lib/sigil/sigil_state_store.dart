import 'dart:io' as io;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// sigil's sync state per emulator and game (`<dir>\<emulator>\<rom id>.state`):
/// what the last sync left, so the next collect knows what changed. Inside
/// the profile, so it travels with the portable folder.
class SigilStateStore {
  SigilStateStore(this.dir);
  final String dir;

  String _file(String emulatorId, String gameId) =>
      p.join(dir, emulatorId, '${gameId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.state');

  Uint8List? read(String emulatorId, String gameId) {
    final f = io.File(_file(emulatorId, gameId));
    try {
      return f.existsSync() ? f.readAsBytesSync() : null;
    } catch (_) {
      return null;
    }
  }

  /// Written to a temporary file and renamed, so a crash never leaves half a state.
  void write(String emulatorId, String gameId, Uint8List state) {
    final f = io.File(_file(emulatorId, gameId));
    f.parent.createSync(recursive: true);
    final tmp = io.File('${f.path}.tmp')..writeAsBytesSync(state, flush: true);
    tmp.renameSync(f.path);
  }
}
