import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/romm/romm_models.dart';
import '../l10n/tr.dart';
import '../profiles/json_file.dart';
import '../profiles/path_guard.dart';

/// Why a manual can't be shown.
class ManualUnavailable implements Exception {
  const ManualUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// #232: a game's manual from RomM (`Game.pathManual`, a PDF), kept in the
/// profile's `cache\manuals\<rom id>.pdf` for offline play: fetched when
/// first opened, or with the game's download. Written through the profile's
/// [guard].
class GameManuals {
  GameManuals({required this.guard, required this.dir, this.download});

  final PathGuard guard;

  /// The profile's `cache\manuals\`.
  final String dir;

  /// RomM's copy of a manual by its path; null without RomM.
  final Future<Uint8List> Function(String pathManual)? download;

  /// Where [game]'s manual is kept.
  String fileFor(Game game) => p.join(dir, '${game.id.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_')}.pdf');

  /// [game]'s manual is on this PC.
  bool isKept(Game game) => io.File(fileFor(game)).existsSync();

  /// [game]'s manual on this PC, fetched from RomM when it isn't yet.
  /// Throws [ManualUnavailable] with why not.
  Future<String> open(Game game) async {
    final file = fileFor(game);
    if (io.File(file).existsSync()) return file;
    final path = game.pathManual;
    if (!game.hasManual || path == null) throw ManualUnavailable(tr('RomM has no manual for this game.'));
    final fetch = download;
    if (fetch == null) throw ManualUnavailable(tr('The manual isn\'t on this PC, and RomM can\'t be reached.'));
    final Uint8List bytes;
    try {
      bytes = await fetch(path);
    } on Object catch (e) {
      debugPrint('[Manual] ${game.id}: $e');
      throw ManualUnavailable(tr('RomM didn\'t send the manual.'));
    }
    if (!isPdf(bytes)) {
      debugPrint('[Manual] ${game.id}: not a PDF (${bytes.length} bytes)');
      throw ManualUnavailable(tr('RomM didn\'t send the manual.'));
    }
    await writeBytesAtomic(guard, file, bytes);
    return file;
  }

  /// Fetches [game]'s manual when RomM has one and it isn't kept yet; a
  /// failure is only logged (a downloaded game plays without it).
  Future<void> keep(Game game) async {
    if (!game.hasManual || isKept(game)) return;
    try {
      await open(game);
    } on Object catch (e) {
      debugPrint('[Manual] not kept for ${game.id}: $e');
    }
  }
}

/// [bytes] start like a PDF (`%PDF-`), not an error page.
bool isPdf(List<int> bytes) =>
    bytes.length > 5 &&
    bytes[0] == 0x25 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x44 &&
    bytes[3] == 0x46 &&
    bytes[4] == 0x2D;
