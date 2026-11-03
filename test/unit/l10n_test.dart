import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/l10n/l10n_table.dart';
import 'package:gargosy/l10n/sv.dart';
import 'package:gargosy/l10n/tr.dart';

import '../helpers/profile_test_env.dart';

/// Every `tr('…')` literal in lib/, unescaped.
Set<String> _trKeys() {
  final call = RegExp(r"""\btr\(\s*'((?:[^'\\]|\\.)*)'""");
  String unescape(String s) => s.replaceAllMapped(
    RegExp(r'\\(.)'),
    (m) => switch (m[1]) {
      'n' => '\n',
      't' => '\t',
      final c => c!,
    },
  );
  return {
    for (final f in io.Directory('lib').listSync(recursive: true).whereType<io.File>())
      if (f.path.endsWith('.dart'))
        for (final m in call.allMatches(f.readAsStringSync())) unescape(m[1]!),
  };
}

void main() {
  tearDown(() => showLanguage(AppLanguage.en));

  final languages = [
    for (final l in AppLanguage.values)
      if (l.table != null) l,
  ];

  test('there are languages besides English', () {
    expect(languages.map((l) => l.name), containsAll(['sv', 'de', 'nl', 'nb', 'da', 'fi']));
  });

  for (final l in languages) {
    test('every tr() text in lib/ is in ${l.name} (#191, #239)', () {
      final keys = _trKeys();
      expect(keys.length, greaterThan(700), reason: 'the scan found the calls');
      expect([
        for (final k in keys)
          if (!l.table!.containsKey(k)) k,
      ], isEmpty);
    });

    test('each ${l.name} text has the same placeholders as its English', () {
      final table = l.table!;
      final wrong = [
        for (final k in table.keys)
          if (!samePlaceholders(k, table[k]!)) k,
      ];
      expect(wrong, isEmpty);
    });

    // Not every text is a tr('…') literal (an enum's label goes through a
    // field), so a removed text is found by the Swedish table, edited by hand.
    test('each ${l.name} text starts and ends with the spaces its English has', () {
      final table = l.table!;
      expect([
        for (final k in table.keys)
          if (!sameEdges(k, table[k]!)) k,
      ], isEmpty);
    });

    test('${l.name} has the same texts as the Swedish table, no more', () {
      expect(l.table!.keys.toSet().difference(svText.keys.toSet()), isEmpty);
    });
  }

  test('a language shows its own text, dates and decimal comma', () async {
    await showLanguage(AppLanguage.de);
    expect(tr('Who sees {0}?', ['Couch']), 'Wer sieht Couch?');
    expect(decimal(9.5, 1), '9,5');
    await showLanguage(AppLanguage.nl);
    expect(tr('Who sees {0}?', ['Couch']), 'Wie ziet Couch?');
    expect(decimal(9.5, 1), '9,5');
    await showLanguage(AppLanguage.nb);
    expect(tr('Who sees {0}?', ['Couch']), 'Hvem ser Couch?');
    expect(decimal(9.5, 1), '9,5', reason: 'intl knows nb, not nb_NO');
    await showLanguage(AppLanguage.da);
    expect(tr('Who sees {0}?', ['Couch']), 'Hvem ser Couch?');
    expect(decimal(9.5, 1), '9,5');
    await showLanguage(AppLanguage.fi);
    expect(tr('Who sees {0}?', ['Couch']), 'Kuka näkee: Couch?');
    expect(decimal(9.5, 1), '9,5');
  });

  test('English is the text itself; Swedish from the table; unknown text stays English', () async {
    expect(tr('Who sees {0}?', ['Couch']), 'Who sees Couch?');
    await showLanguage(AppLanguage.sv);
    expect(tr('Who sees {0}?', ['Couch']), 'Vem ser Couch?');
    expect(tr('Not in the table {0}', [1]), 'Not in the table 1');
    expect(decimal(9.5, 1), '9,5');
    await showLanguage(AppLanguage.en);
    expect(decimal(9.5, 1), '9.5');
  });

  test('placeholders: in any order, braces doubled, missing args left as they are', () {
    expect(fillPlaceholders('{1} then {0}', ['a', 'b']), 'b then a');
    expect(fillPlaceholders('{{0}} is {0}', ['x']), '{0} is x');
    expect(fillPlaceholders('{2}', ['a']), '{2}');
  });

  test("System is Windows' language when Gargosy has it, else English; the pref is app-wide", () {
    expect(AppLanguage.system.resolve('sv'), AppLanguage.sv);
    expect(AppLanguage.system.resolve('de'), AppLanguage.de);
    expect(AppLanguage.system.resolve('nl'), AppLanguage.nl);
    expect(AppLanguage.system.resolve('nb'), AppLanguage.nb);
    expect(AppLanguage.system.resolve('no'), AppLanguage.nb, reason: 'Windows may say no or nn');
    expect(AppLanguage.system.resolve('nn'), AppLanguage.nb);
    expect(AppLanguage.system.resolve('da'), AppLanguage.da);
    expect(AppLanguage.system.resolve('fi'), AppLanguage.fi);
    expect(AppLanguage.system.resolve('ja'), AppLanguage.en);
    expect(AppLanguage.en.resolve('sv'), AppLanguage.en);
    final prefs = MemoryPrefs();
    expect(AppLanguage.of(prefs), AppLanguage.system);
    prefs.values[AppLanguage.prefKey] = 'sv';
    expect(AppLanguage.of(prefs), AppLanguage.sv);
    prefs.values[AppLanguage.prefKey] = 'klingon';
    expect(AppLanguage.of(prefs), AppLanguage.system);
  });
}
