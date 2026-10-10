import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/storage/app_preferences.dart';
import 'sigil_engine.dart';

/// Reads a game's id from its ROM through sigil.
typedef IdentifyRom = Future<SigilId?> Function(String path, {String? platform});

/// The PS1/PS2 disc serial (`SLUS-20152`) of a ROM, read through sigil
/// (CHD, ISO, BIN/CUE, CSO, PBP, …; the file name when the disc gives none),
/// remembered per file so a ROM is read once. Replaces Freegosy's serial
/// extraction service and CHD reader.
class RomGameIds {
  RomGameIds(this._prefs, {IdentifyRom? identify}) : _identify = identify ?? SigilEngine.identify;

  final AppPreferences _prefs;
  final IdentifyRom _identify;

  static final _serialShape = RegExp(r'^[A-Z]{4}-\d{5}$');

  /// The key the old serial service used, so serials it remembered stay.
  static String _key(String romPath) => 'disc_serial_${p.absolute(romPath)}';

  /// `SLUS_201.52` / `slus-201.52` → `SLUS-20152`, the form save folders use.
  static String normalizeSerial(String raw) =>
      raw.toUpperCase().replaceAll('_', '-').replaceAllMapped(RegExp(r'(\d{3})\.(\d{2})'), (m) => '${m[1]}${m[2]}');

  /// [romPath]'s serial for [platform] (RomM's slug: `ps2`, `psx`), or null
  /// when it can't be read. Never throws.
  Future<String?> discSerial(String romPath, {required String platform}) async {
    final remembered = _prefs.getString(_key(romPath))?.trim().toUpperCase();
    if (remembered != null && _serialShape.hasMatch(remembered)) {
      debugPrint('[GameId] remembered serial for $romPath: $remembered');
      return remembered;
    }
    SigilId? id;
    try {
      id = await _identify(await _dataTrack(romPath), platform: platform);
    } catch (e) {
      debugPrint('[GameId] reading $romPath failed: $e');
    }
    if (id == null) {
      // sigil reads the name only after opening the file; a ROM it couldn't
      // open (missing, locked) still has the serial its name gives.
      final named = _fromName(romPath);
      debugPrint('[GameId] sigil read no serial from $romPath${named == null ? '' : '; from its name: $named'}');
      return named;
    }
    final serial = normalizeSerial(id.titleId);
    debugPrint('[GameId] serial from ${id.fromBinary ? 'the disc' : 'the file name'}: $serial');
    if (_serialShape.hasMatch(serial)) {
      try {
        await _prefs.setString(_key(romPath), serial);
      } catch (e) {
        debugPrint('[GameId] could not remember the serial: $e');
      }
    }
    return serial;
  }

  /// A serial in the file name, as No-Intro/Redump sets give it:
  /// `Ico (SCUS-97113)`, `Game [SLUS_201.52]`.
  static String? _fromName(String romPath) {
    final m = RegExp(
      r'\b(S[A-Z]{3,4}[-_]\d{3}[._]?\d{2})\b',
      caseSensitive: false,
    ).firstMatch(p.basenameWithoutExtension(romPath));
    return m == null ? null : normalizeSerial(m.group(1)!);
  }

  /// A multi-track disc (PS1 games with CD audio) is several .bin files and
  /// only Track 01 holds the boot data. Callers may pass any track (a
  /// "largest file" pick), so a sibling .cue naming [romPath] resolves it to
  /// that sheet's first FILE. Anything else is returned unchanged.
  static Future<String> _dataTrack(String romPath) async {
    if (p.extension(romPath).toLowerCase() != '.bin') return romPath;
    final dir = io.Directory(p.dirname(romPath));
    final name = p.basename(romPath);
    try {
      await for (final entity in dir.list()) {
        if (entity is! io.File || p.extension(entity.path).toLowerCase() != '.cue') continue;
        final files = [
          for (final line in await entity.readAsLines())
            RegExp(r'^\s*FILE\s+"([^"]+)"\s+BINARY', caseSensitive: false).firstMatch(line)?.group(1),
        ].whereType<String>().toList();
        if (files.isEmpty || !files.any((f) => p.basename(f) == name)) continue;
        final data = p.join(dir.path, p.basename(files.first));
        if (await io.File(data).exists()) return data;
        break;
      }
    } catch (_) {}
    return romPath;
  }
}
