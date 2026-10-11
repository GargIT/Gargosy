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
