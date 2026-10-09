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
