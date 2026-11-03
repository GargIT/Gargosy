// Making a language's table (#239), for tool/l10n.dart and the tests: no
// Flutter here, so the tool runs on plain Dart.

/// The `{0}`, `{1}` … in [text] (not `{{0}}`, which is a brace).
Set<String> placeholdersOf(String text) => {for (final m in RegExp(r'(?<!\{)\{(\d+)\}').allMatches(text)) m[1]!};

bool samePlaceholders(String a, String b) {
  final x = placeholdersOf(a), y = placeholdersOf(b);
  return x.length == y.length && x.containsAll(y);
}

/// [translation] with the spaces at [english]'s start and end: a text that
/// is put together with others keeps its gap, though editors strip spaces
/// at a line's end.
String withEdgesOf(String english, String translation) {
  final lead = RegExp(r'^\s*').stringMatch(english)!;
  final trail = RegExp(r'\s*$').stringMatch(english)!;
  if (lead.isEmpty && trail.isEmpty) return translation;
  return '$lead${translation.trim()}$trail';
}

/// Whether [a] and [b] start and end with the same spaces.
bool sameEdges(String a, String b) =>
    RegExp(r'^\s*').stringMatch(a) == RegExp(r'^\s*').stringMatch(b) &&
    RegExp(r'\s*$').stringMatch(a) == RegExp(r'\s*$').stringMatch(b);

/// A language code a table may have: two or three small letters, as
/// Windows names the language (`de`, `nb`), so System can pick it.
bool isLanguageCode(String code) => RegExp(r'^[a-z]{2,3}$').hasMatch(code);

/// [keys] (every English text, in order) as one line each, numbered from 1,
/// after a first line with their [fingerprint]: a file translated from
/// another set of texts is refused, so no line lands on the wrong text.
String exportLines(List<String> keys) =>
    ['# texts ${fingerprint(keys)}', for (var i = 0; i < keys.length; i++) '${i + 1}\t${_line(keys[i])}'].join('\n');

/// FNV-1a of the texts, in order.
String fingerprint(List<String> keys) {
  var h = 0x811c9dc5;
  for (final unit in keys.join('\u0000').codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// The translations in [text] (lines `<n>\t<translation>`) of [keys], by
/// number: every number once, each keeping its English's placeholders, from
/// an export of these same texts.
Map<int, String> parseTranslations(String text, List<String> keys) {
  final got = <int, String>{};
  var lines = text.split(RegExp(r'\r?\n'));
  if (lines.isNotEmpty) lines[0] = lines[0].replaceFirst('\uFEFF', '');
  for (final raw in lines) {
    if (raw.trim().isEmpty) continue;
    if (raw.startsWith('#')) {
      final printed = RegExp(r'^# texts ([0-9a-f]+)').firstMatch(raw)?.group(1);
      if (printed != null && printed != fingerprint(keys)) {
        throw StateError(
          'Gargosy\'s texts changed since this file was exported: export again and carry the translations over.',
        );
      }
      continue;
    }
    final tab = raw.indexOf('\t');
    final n = tab < 0 ? null : int.tryParse(raw.substring(0, tab));
    if (n == null || n < 1 || n > keys.length) throw FormatException('not a numbered line', raw);
    if (got.containsKey(n)) throw FormatException('$n twice', raw);
    got[n] = withEdgesOf(keys[n - 1], _unline(raw.substring(tab + 1)));
  }
  final missing = [
    for (var i = 1; i <= keys.length; i++)
      if (!got.containsKey(i)) i,
  ];
  if (missing.isNotEmpty) throw StateError('missing: ${missing.take(20).join(', ')}');
  final lost = [
    for (var i = 1; i <= keys.length; i++)
      if (!samePlaceholders(keys[i - 1], got[i]!)) i,
  ];
  if (lost.isNotEmpty) throw StateError('placeholders differ: ${lost.join(', ')}');
  return got;
}

/// The Dart source of `lib/l10n/<code>.dart`: [keys] to their [translations].
String tableSource(String code, String name, List<String> keys, Map<int, String> translations) {
  if (!isLanguageCode(code)) throw ArgumentError.value(code, 'code', 'two or three small letters');
  final out = StringBuffer()
    ..writeln('// The $name text of Gargosy (#239), by its English text (the key tr looks')
    ..writeln('// up). Made with tool/l10n.dart; corrections are welcome by pull request')
    ..writeln('// (docs/translating.md). Placeholders {0}, {1} … are filled by tr.')
    ..writeln()
    ..writeln('const ${code}Text = <String, String>{');
  for (var i = 0; i < keys.length; i++) {
    out.writeln('  ${dartString(keys[i])}: ${dartString(translations[i + 1]!)},');
  }
  out.writeln('};');
  return out.toString();
}

/// [s] as a single-quoted Dart string.
String dartString(String s) =>
    "'${s.replaceAll('\\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n')}'";

String _line(String s) => s.replaceAll('\\', r'\\').replaceAll('\n', r'\n').replaceAll('\t', r'\t');

String _unline(String s) => s.replaceAllMapped(
  RegExp(r'\\(.)'),
  (m) => switch (m[1]) {
    'n' => '\n',
    't' => '\t',
    final c => c!,
  },
);
