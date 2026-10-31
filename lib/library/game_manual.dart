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
/// profile's `cache\manuals\<rom id>.pdf` once opened, so it opens offline
/// too. Written through the profile's [guard].
class GameManuals {
  GameManuals({required this.guard, required this.dir, this.download});

  final PathGuard guard;

  /// The profile's `cache\manuals\`.
  final String dir;

  /// RomM's copy of a manual by its path; null without RomM.
  final Future<Uint8List> Function(String pathManual)? download;

  /// Fetches under way, by file: a second open waits for the first instead
  /// of writing the same file. Shared by every [GameManuals] (the provider
  /// builds a new one when RomM comes and goes).
  static final _fetching = <String, Future<String>>{};

  /// Where [game]'s manual is kept.
  String fileFor(Game game) => p.join(dir, '${game.id.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_')}.pdf');

  /// [game]'s manual is on this PC.
  bool isKept(Game game) => io.File(fileFor(game)).existsSync();

  /// [game]'s manual on this PC, fetched from RomM when it isn't yet.
  /// Throws [ManualUnavailable] with why not.
  Future<String> open(Game game) {
    final file = fileFor(game);
    if (io.File(file).existsSync()) return Future.value(file);
    final key = guard.pathKey(file);
    return _fetching[key] ??= _fetch(game, file).whenComplete(() {
      _fetching.remove(key);
    });
  }

  Future<String> _fetch(Game game, String file) async {
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

  /// Removes [game]'s kept manual: a copy PDFium can't open (fetched again
  /// next time), or the game leaving this PC. Nothing kept is fine.
  Future<void> forget(Game game) async {
    final file = io.File(guard.check(fileFor(game)));
    try {
      if (file.existsSync()) await file.delete();
    } on io.FileSystemException catch (e) {
      debugPrint('[Manual] ${game.id} not removed: $e');
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
