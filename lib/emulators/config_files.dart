import '../core/storage/ini_file.dart';

/// Sets `key = "value"` lines in a RetroArch cfg, replacing an existing line
/// for the key or appending one. Other lines are kept as they are.
String setRetroArchKeys(String text, Map<String, String> values) {
  final lines = text.isEmpty ? <String>[] : text.split(RegExp(r'\r?\n'));
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  for (final e in values.entries) {
    final line = '${e.key} = "${e.value}"';
    final i = lines.indexWhere((l) => RegExp('^\\s*${RegExp.escape(e.key)}\\s*=').hasMatch(l));
    if (i >= 0) {
      lines[i] = line;
    } else {
      lines.add(line);
    }
  }
  return '${lines.join('\n')}\n';
}

/// Sets `key = 'value'` lines in one [section] of a TOML file (xemu's), adding
/// the section when missing. Other lines are kept as they are.
String setTomlKeys(String text, String section, Map<String, String> values) {
  final lines = text.isEmpty ? <String>[] : text.split(RegExp(r'\r?\n'));
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  var start = lines.indexWhere((l) => l.trim() == '[$section]');
  if (start < 0) {
    lines
      ..add('')
      ..add('[$section]');
    start = lines.length - 1;
  }
  var end = lines.indexWhere((l) => l.trim().startsWith('['), start + 1);
  if (end < 0) end = lines.length;
  for (final e in values.entries) {
    final line = "${e.key} = '${e.value}'";
    final i = lines.sublist(start + 1, end).indexWhere((l) => RegExp('^\\s*${RegExp.escape(e.key)}\\s*=').hasMatch(l));
    if (i >= 0) {
      lines[start + 1 + i] = line;
    } else {
      lines.insert(end, line);
      end++;
    }
  }
  return '${lines.join('\n')}\n';
}

/// The value of `key = '…'` in one [section] of a TOML file (xemu's), or
/// null when it isn't there.
String? getTomlKey(String text, String section, String key) {
  String? current;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      current = line;
      continue;
    }
    if (current != '[$section]') continue;
    final m = RegExp('^${RegExp.escape(key)}' r'''\s*=\s*(['"])(.*)\1\s*$''').firstMatch(line);
    if (m != null) return m.group(2);
  }
  return null;
}

/// [ini] (a Qt settings file, Eden's and Azahar's `qt-config.ini`) with
/// [paths] added to the array [array] in [section] (`Paths\gamedirs`):
/// `<array>\<n>\path`, `deep_scan`, `expanded`, and `<array>\size`. Folders
/// already listed (any case or slash) stay as they are, and so does every
/// other key. False when the file has no such array yet (before the
/// emulator's first run): its own defaults come first, then the folders on
/// the next launch.
bool addQtArrayPaths(IniFile ini, String section, String array, List<String> paths) {
  final sizeKey = '$array\\size';
  final size = int.tryParse(ini.get(section, sizeKey) ?? '');
  if (size == null) return false;
  String norm(String s) => s.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();
  final have = {
    for (var i = 1; i <= size; i++)
      if (ini.get(section, '$array\\$i\\path') case final v?) norm(v),
  };
  var n = size;
  for (final path in paths) {
    final qt = path.replaceAll('\\', '/');
    if (!have.add(norm(qt))) continue;
    n++;
    ini.set(section, '$array\\$n\\deep_scan', 'false');
    ini.set(section, '$array\\$n\\expanded', 'true');
    ini.set(section, '$array\\$n\\path', qt);
  }
  if (n != size) ini.set(section, sizeKey, '$n');
  return true;
}
