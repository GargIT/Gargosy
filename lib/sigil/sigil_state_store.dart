import 'dart:convert';
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
  void write(String emulatorId, String gameId, Uint8List state) => _write(_file(emulatorId, gameId), state);

  void _write(String path, List<int> bytes) {
    final f = io.File(path);
    f.parent.createSync(recursive: true);
    final tmp = io.File('${f.path}.tmp')..writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(f.path);
  }

  String _claimsFile(String emulatorId, String gameId) => p.setExtension(_file(emulatorId, gameId), '.claims.json');

  /// The unclaimed saves the player said are this game's (#56), waiting for
  /// an upload to commit them; empty when none (or the file can't be read).
  List<String> claims(String emulatorId, String gameId) {
    final f = io.File(_claimsFile(emulatorId, gameId));
    try {
      if (!f.existsSync()) return const [];
      final list = jsonDecode(f.readAsStringSync());
      return list is List
          ? [
              for (final n in list)
                if (n is String) n,
            ]
          : const [];
    } catch (_) {
      return const [];
    }
  }

  /// [names] become the game's waiting claims; none removes the file.
  void setClaims(String emulatorId, String gameId, List<String> names) {
    final path = _claimsFile(emulatorId, gameId);
    if (names.isEmpty) {
      final f = io.File(path);
      if (f.existsSync()) f.deleteSync();
      return;
    }
    _write(path, utf8.encode(jsonEncode(names)));
  }
}
