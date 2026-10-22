import 'dart:io' as io;
import 'dart:typed_data';

/// Gargosy (#94): what deleting one game's save on this PC changes, as its
/// save strategy plans it (`SaveStrategy.saveDeletionFor`).
class LocalSaveDeletion {
  const LocalSaveDeletion({this.files = const [], this.folders = const [], this.cards = const {}});

  /// Files that are the game's save alone: deleted.
  final List<io.File> files;

  /// Folders that each hold one of the game's saves (a PCSX2 folder card's
  /// `BASLUS-20328SAVE`, PSP's `SAVEDATA\ULUS10064DATA`): deleted whole.
  final List<io.Directory> folders;

  /// Card files other games' saves share, by path: written again as given,
  /// without the game's saves.
  final Map<String, Uint8List> cards;

  /// Folders and cards other games' saves sit beside: copied whole before
  /// anything changes.
  Iterable<String> get shared => [for (final d in folders) d.path, ...cards.keys];

  /// Every path the deletion writes or deletes.
  Iterable<String> get paths => [for (final f in files) f.path, ...shared];
}
