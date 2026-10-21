import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/letter_index.dart';

import '../helpers/game_fixtures.dart';

void main() {
  test('a name goes under its first letter, any case; digits and symbols under #', () {
    expect(
      [railLetterOf('ico'), railLetterOf('Zone'), railLetterOf('1942'), railLetterOf('.hack'), railLetterOf('')],
      ['I', 'Z', '#', '#', '#'],
    );
  });

  test("RomM's char_index: letters upper-cased, every digit and symbol under # at the earliest", () {
    expect(railIndexOf({'0': 3, '.': 0, 'a': 5, 'b': 9, 'é': 40}), {'#': 0, 'A': 5, 'B': 9});
  });

  test('On this PC: the first game under each letter, by its shown name', () {
    final games = [game(1, '.hack Infection'), game(2, 'Ape Escape'), game(3, 'ape 2'), game(4, 'Rez')];
    expect(railIndexOfGames(games), {'#': 0, 'A': 1, 'R': 3});
  });

  test('the rail is # then A to Z', () {
    expect(railLetters.length, 27);
    expect(railLetters.first, '#');
    expect(railLetters.last, 'Z');
  });
}
