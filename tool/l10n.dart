// Translations (#239): `dart tool/l10n.dart export <file>` writes every
// text to translate, one a line, numbered (`<n>\t<English>`, a line break as
// `\n`); `dart tool/l10n.dart build <code> <name> <file>` makes
// `lib/l10n/<code>.dart` from such a file with the English replaced by the
// translation (`<n>\t<translation>`). The numbers are the English texts'
// order in `svText` (every text Gargosy has); a line missing, a number
// twice or a placeholder lost stops it.
import 'dart:io';

import 'package:gargosy/l10n/sv.dart';

void main(List<String> args) {
  if (args.length == 2 && args[0] == 'export') return _export(args[1]);
  if (args.length == 4 && args[0] == 'build') return _build(args[1], args[2], args[3]);
  stderr.writeln('dart run tool/l10n.dart export <file> | build <code> <name> <file>');
  exitCode = 2;
}

List<String> get _keys => svText.keys.toList();

String _line(String s) => s.replaceAll('\\', r'\\').replaceAll('\n', r'\n').replaceAll('\t', r'\t');

String _unline(String s) => s.replaceAllMapped(
  RegExp(r'\\(.)'),
  (m) => switch (m[1]) {
    'n' => '\n',
    't' => '\t',
    final c => c!,
  },
);

void _export(String path) {
  final keys = _keys;
  File(path).writeAsStringSync([for (var i = 0; i < keys.length; i++) '${i + 1}\t${_line(keys[i])}'].join('\n'));
  stdout.writeln('${keys.length} texts');
}

Set<String> _placeholders(String s) => {for (final m in RegExp(r'(?<!\{)\{(\d+)\}').allMatches(s)) m[1]!};

String _dart(String s) => "'${s.replaceAll('\\', r'\\').replaceAll("'", r"\'").replaceAll('\n', r'\n')}'";

void _build(String code, String name, String path) {
  final keys = _keys;
  final got = <int, String>{};
  for (final raw in File(path).readAsLinesSync()) {
    if (raw.trim().isEmpty) continue;
    final tab = raw.indexOf('\t');
    final n = tab < 0 ? null : int.tryParse(raw.substring(0, tab));
    if (n == null || n < 1 || n > keys.length) throw FormatException('not a numbered line', raw);
    if (got.containsKey(n)) throw FormatException('$n twice', raw);
    got[n] = _unline(raw.substring(tab + 1));
  }
  final missing = [
    for (var i = 1; i <= keys.length; i++)
      if (!got.containsKey(i)) i,
  ];
  if (missing.isNotEmpty) throw StateError('missing: ${missing.take(20).join(', ')}');
  final lost = [
    for (var i = 1; i <= keys.length; i++)
      if (!_setEquals(_placeholders(keys[i - 1]), _placeholders(got[i]!))) i,
  ];
  if (lost.isNotEmpty) throw StateError('placeholders differ: ${lost.join(', ')}');
  final out = StringBuffer()
    ..writeln('// The $name text of Gargosy (#239), by its English text (the key tr looks')
    ..writeln('// up). Made with tool/l10n.dart; corrections are welcome by pull request')
    ..writeln('// (docs/translating.md). Placeholders {0}, {1} … are filled by tr.')
    ..writeln()
    ..writeln('const ${code}Text = <String, String>{');
  for (var i = 0; i < keys.length; i++) {
    out.writeln('  ${_dart(keys[i])}: ${_dart(got[i + 1]!)},');
  }
  out.writeln('};');
  File('lib/l10n/$code.dart').writeAsStringSync(out.toString());
  stdout.writeln('lib/l10n/$code.dart: ${keys.length} texts');
}

bool _setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
