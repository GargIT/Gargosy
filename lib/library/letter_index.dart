import '../core/romm/romm_models.dart';

/// The A–Z rail's letters, top to bottom: `#` for digits and symbols.
const railLetters = [
  '#',
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
];

/// The rail letter a name (or RomM's sort key) starting with [first] goes under.
String railLetterOf(String first) {
  if (first.isEmpty) return '#';
  final c = first[0].toUpperCase();
  return c.compareTo('A') >= 0 && c.compareTo('Z') <= 0 ? c : '#';
}

/// RomM's `char_index` (first character → offset) as rail letters → the
/// offset of their first game: every digit and symbol goes under `#`, at the
/// earliest of them.
Map<String, int> railIndexOf(Map<String, int> charIndex) {
  final index = <String, int>{};
  for (final e in charIndex.entries) {
    final letter = railLetterOf(e.key);
    final at = index[letter];
    if (at == null || e.value < at) index[letter] = e.value;
  }
  return index;
}

/// The rail for [games] already in their order (On this PC): each letter's
/// first game, by its shown name.
Map<String, int> railIndexOfGames(List<Game> games) {
  final index = <String, int>{};
  for (var i = 0; i < games.length; i++) {
    index.putIfAbsent(railLetterOf(games[i].displayName.trim()), () => i);
  }
  return index;
}
