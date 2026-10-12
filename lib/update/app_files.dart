import 'package:path/path.dart' as p;

/// `app-files.txt`: every app file of a Gargosy build, one relative path a
/// line (`Gargosy.exe`, `data\flutter_assets\…`), written by
/// `tool/make_release.ps1` next to the exe. The updater replaces exactly
/// these and nothing else, so a file the user put in the folder is never
/// touched, and a file dropped from a new version goes.
class AppFiles {
  AppFiles._();

  static const fileName = 'app-files.txt';

  /// Folders that hold the user's things: never on the list.
  static const protected = ['roms', 'emulators', 'bios', 'userdata'];

  /// The paths in [text] (`\` separators, as Windows writes them). Throws a
  /// [FormatException] naming the first line that's absolute, has `..`, is
  /// in a [protected] folder or has a name Windows would change: the whole
  /// list is refused before anything moves, as `GargosyUpdate.exe` does
  /// (`windows/updater/updater.cpp`, `IsSafeRelative`).
  static List<String> parse(String text) {
    final out = <String>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'[\\/]'));
      if (line.startsWith(r'\') || line.startsWith('/') || line.contains(':')) {
        throw FormatException('an absolute path in $fileName', line);
      }
      if (parts.any((s) => s == '..' || s == '.' || s.isEmpty)) {
        throw FormatException('a path that leaves the Gargosy folder in $fileName', line);
      }
      // Windows drops a trailing dot or space ("userdata." is userdata), and
      // an 8.3 name (USERDA~1) could be one of the user's folders too.
      if (RegExp(r'[*?"<>|]').hasMatch(line) || parts.any((s) => s.endsWith('.') || s.endsWith(' '))) {
        throw FormatException('a name Windows would change in $fileName', line);
      }
      if (protected.contains(parts.first.toLowerCase()) || parts.first.contains('~')) {
        throw FormatException("a path in the user's folders in $fileName", line);
      }
      out.add(parts.join(r'\'));
    }
    if (out.isEmpty) throw const FormatException('$fileName is empty');
    return out;
  }

  /// [relative] (from [parse]) under [dir], with this platform's separators.
  static String under(String dir, String relative) => p.joinAll([dir, ...relative.split(r'\')]);
}
