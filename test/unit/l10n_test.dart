import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
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

Set<String> _placeholders(String s) => {for (final m in RegExp(r'(?<!\{)\{(\d+)\}').allMatches(s)) m[1]!};

void main() {
  tearDown(() => showLanguage(AppLanguage.en));

  test("every tr() text in lib/ has its Swedish (#191)", () {
    final keys = _trKeys();
    expect(keys.length, greaterThan(700), reason: 'the scan found the calls');
    expect([
      for (final k in keys)
        if (!svText.containsKey(k)) k,
    ], isEmpty);
  });

  test('each Swedish text has the same placeholders as its English', () {
    final wrong = [
      for (final k in svText.keys)
        if (!setEquals(_placeholders(k), _placeholders(svText[k]!))) k,
    ];
    expect(wrong, isEmpty);
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
    expect(AppLanguage.system.resolve('de'), AppLanguage.en);
    expect(AppLanguage.en.resolve('sv'), AppLanguage.en);
    final prefs = MemoryPrefs();
    expect(AppLanguage.of(prefs), AppLanguage.system);
    prefs.values[AppLanguage.prefKey] = 'sv';
    expect(AppLanguage.of(prefs), AppLanguage.sv);
    prefs.values[AppLanguage.prefKey] = 'klingon';
    expect(AppLanguage.of(prefs), AppLanguage.system);
  });
}

bool setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
