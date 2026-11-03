// Translations (#239), run from the Gargosy folder with
// `dart --packages=.dart_tool/package_config.json tool/l10n.dart …`
// (`dart run` builds pdfrx's native hooks first):
// `export <file>` writes every text to translate, one a line, numbered
// (`<n>\t<English>`, a line break as `\n`), after a line naming this set of
// texts; `build <code> <name> <file>` makes `lib/l10n/<code>.dart` from such
// a file with the English replaced by the translation, and formats it. A
// line missing, a number twice, a placeholder lost or a file exported from
// other texts stops it (`lib/l10n/l10n_table.dart`).
import 'dart:io';

import 'package:gargosy/l10n/l10n_table.dart';
import 'package:gargosy/l10n/sv.dart';

void main(List<String> args) {
  final keys = svText.keys.toList();
  if (args.length == 2 && args[0] == 'export') {
    File(args[1]).writeAsStringSync(exportLines(keys));
    stdout.writeln('${keys.length} texts');
    return;
  }
  if (args.length == 4 && args[0] == 'build') {
    final code = args[1];
    final source = tableSource(code, args[2], keys, parseTranslations(File(args[3]).readAsStringSync(), keys));
    final path = 'lib/l10n/$code.dart';
    File(path).writeAsStringSync(source);
    Process.runSync('dart', ['format', path], runInShell: true);
    stdout.writeln('$path: ${keys.length} texts');
    return;
  }
  stderr.writeln('dart tool/l10n.dart export <file> | build <code> <name> <file>');
  exitCode = 2;
}
