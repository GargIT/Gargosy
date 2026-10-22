import 'dart:io' as io;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/save/formats/ps1_memory_card.dart';
import '../core/save/formats/ps2_memory_card.dart';
import '../core/save/local_save_deletion.dart';
import '../core/save/save_strategy.dart';

/// Gargosy (#94): one game's save on this PC, as sigil's collect found it
/// for the game ([read]: the files it read, full paths; [unit]: what it
/// collected), planned for deleting. sigil picks the game's saves, so
/// nothing here guesses from ids:
/// - a file in a save folder (a PCSX2 folder card's, PSP's `SAVEDATA`):
///   sigil read only the game's folders, and each goes whole;
/// - a PS1 or PS2 card file: the unit is a card holding only the game's
///   saves, and those come off the card; the other games' stay;
/// - anything else is refused before anything changes.
LocalSaveDeletion planSigilSaveDeletion(List<String> read, Uint8List? unit) {
  final folders = <String>{};
  final cards = <String, Uint8List>{};
  Set<String>? gameSaves;
  Set<String> unitSaves(String card) {
    final names = gameSaves ??= _saveNames(unit);
    if (names == null || names.isEmpty) {
      throw SaveSyncNotPossibleException("Gargosy can't tell this game's saves apart on ${p.basename(card)}");
    }
    return names;
  }

  for (final path in read) {
    final folder = p.dirname(path);
    if (_isSaveFolder(folder)) {
      folders.add(folder);
      continue;
    }
    final Uint8List bytes;
    try {
      bytes = io.File(path).readAsBytesSync();
    } on io.FileSystemException catch (e) {
      throw SaveSyncNotPossibleException("${p.basename(path)} can't be read (${e.osError?.message ?? e.message})");
    }
    try {
      final Uint8List? without;
      if (Ps1MemoryCard.looksLikeCard(bytes)) {
        final names = unitSaves(path);
        without = Ps1MemoryCard.parse(bytes).withoutSaves(names.contains);
      } else if (Ps2MemoryCard.looksLikeCard(bytes)) {
        final names = unitSaves(path);
        final card = Ps2MemoryCard.parse(bytes);
        without = card.saves.any((s) => names.contains(s.name)) ? card.withSaves(const [], names.contains) : null;
      } else {
        throw SaveSyncNotPossibleException("Gargosy can't take one game's save off ${p.basename(path)} yet");
      }
      if (without != null) cards[path] = without;
    } on FormatException catch (e) {
      throw SaveSyncNotPossibleException("${p.basename(path)} isn't a card Gargosy can change (${e.message})");
    }
  }
  if (folders.isEmpty && cards.isEmpty) throw SaveSyncNotPossibleException('there is no save on this PC');
  return LocalSaveDeletion(folders: [for (final f in folders) io.Directory(f)], cards: cards);
}

/// A folder holding one save: one in a PCSX2 folder card (its parent has
/// `_pcsx2_superblock`) or in PSP's `SAVEDATA`.
bool _isSaveFolder(String folder) {
  final parent = p.dirname(folder);
  return p.basename(parent).toUpperCase() == 'SAVEDATA' || io.File(p.join(parent, '_pcsx2_superblock')).existsSync();
}

/// The saves on sigil's unit, when it's a PS1 or PS2 card.
Set<String>? _saveNames(Uint8List? unit) {
  if (unit == null) return null;
  try {
    if (Ps1MemoryCard.looksLikeCard(unit)) return {for (final s in Ps1MemoryCard.parse(unit).saves) s.name};
    if (Ps2MemoryCard.looksLikeCard(unit)) return {for (final s in Ps2MemoryCard.parse(unit).saves) s.name};
  } on FormatException {
    return null;
  }
  return null;
}
