// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy (#57): sigil moves PS2 saves on and off the cards now; what's left
// is what RetroArch's LRPS2 still asks: shared or per-game cards, and which
// saves are a game's.

/// PS2 saves as RetroArch's LRPS2 keeps them: in RetroArch's system folder,
/// shared by every game (`pcsx2/memcards/Mcd001.ps2`, `Mcd002.ps2`), or, with
/// its *Shared Memory Cards* option off, one card per game in the save folder
/// (`<content>.ps2`). A game's saves on a card are its **save folders** (e.g.
/// `BASLUS-20851AC5/…`).
class Ps2SaveFolders {
  Ps2SaveFolders._();

  /// The option that picks shared or per-game cards, and its default.
  static const lrps2SharedCardsOption = 'pcsx2_shared_memory_cards';

  /// Whether LRPS2 uses its shared cards, from the contents of the core
  /// option files that apply, most specific first (the game's, its folder's,
  /// the core's, RetroArch's global one). Shared unless one says otherwise.
  static bool lrps2UsesSharedCards(List<String> optionFiles) {
    final line = RegExp('^\\s*$lrps2SharedCardsOption\\s*=\\s*"?(enabled|disabled)"?', multiLine: true);
    for (final contents in optionFiles) {
      final m = line.firstMatch(contents);
      if (m != null) return m.group(1) == 'enabled';
    }
    return true;
  }

  /// Whether the save folder [name] belongs to the game with [serial]
  /// (e.g. `SLUS-20851`). PS2 save folders are named
  /// `<region prefix><serial><suffix>`: `BASLUS-20851AC5`, `BESCES-52438GAMEDATA`.
  static bool isSaveOf(String name, String serial) {
    final s = serial.toUpperCase().replaceAll('_', '-');
    final n = name.toUpperCase().replaceAll('_', '-');
    return n.length >= 2 + s.length && n.substring(2, 2 + s.length) == s;
  }
}
