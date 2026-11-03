import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/l10n/l10n_table.dart';

void main() {
  const keys = ['Play', 'Who sees {0}?', 'Line one\nline two', 'It\'s \$5 and a \\ back'];

  String translated(String exported, List<String> texts) {
    final lines = exported.split('\n');
    return [lines.first, for (var i = 0; i < texts.length; i++) '${i + 1}\t${texts[i]}'].join('\n');
  }

  test('export then build round-trips line breaks, tabs, quotes, dollars and backslashes', () {
    final exported = exportLines(keys);
    expect(exported.split('\n'), hasLength(keys.length + 1));
    expect(exported.split('\n')[3], r'3	Line one\nline two');
    final got = parseTranslations(
      translated(exported, ['Spielen', 'Wer sieht {0}?', r'Zeile eins\nZeile zwei', r'Es kostet $5 und ein \\ zurück']),
      keys,
    );
    expect(got[3], 'Zeile eins\nZeile zwei');
    expect(got[4], r'Es kostet $5 und ein \ zurück');
    final source = tableSource('de', 'German', keys, got);
    expect(source, contains(r"'Es kostet \$5 und ein \\ zurück'"), reason: r'a $ is never interpolation');
    expect(source, contains(r"'It\'s \$5 and a \\ back'"));
    expect(source, contains('const deText = <String, String>{'));
  });

  test('a missing line, a number twice, a lost placeholder or another set of texts is refused', () {
    final exported = exportLines(keys);
    expect(() => parseTranslations(translated(exported, ['a', 'b {0}', 'c']), keys), throwsStateError);
    expect(() => parseTranslations('1\ta\n1\tb', keys), throwsFormatException);
    expect(() => parseTranslations(translated(exported, ['a', 'b', 'c', 'd']), keys), throwsStateError);
    expect(
      () => parseTranslations(translated(exportLines(['Other']), ['a', 'b {0}', 'c', 'd']), keys),
      throwsStateError,
    );
  });

  test('a byte order mark from a Windows editor is no problem', () {
    final text = '﻿${translated(exportLines(keys), ['a', 'b {0}', 'c', 'd'])}';
    expect(parseTranslations(text, keys)[1], 'a');
  });

  test('a language code is two or three small letters, as Windows names the language', () {
    expect(isLanguageCode('de'), isTrue);
    expect(isLanguageCode('fil'), isTrue);
    expect(isLanguageCode('pt-BR'), isFalse);
    expect(() => tableSource('pt-BR', 'x', const [], const {}), throwsArgumentError);
  });

  test('placeholders: {0} counts, {{0}} is a brace', () {
    expect(placeholdersOf('{1} of {0}'), {'0', '1'});
    expect(placeholdersOf('{{0}} is {0}'), {'0'});
    expect(samePlaceholders('{0} and {1}', '{1} und {0}'), isTrue);
    expect(samePlaceholders('{0}', 'nothing'), isFalse);
  });
}
