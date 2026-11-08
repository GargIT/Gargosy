/// Paths into a profile's folder inside an emulator settings template
/// (#301): a template is made from one profile and copied into new ones, so
/// a path into the profile it came from is kept as a marker and becomes the
/// new profile's folder when it's copied. Without it the new profile's
/// emulator would write into the other profile's folder (or a deleted one).
library;

/// The note in `userdata\templates\<emu>\` that says Gargosy made the
/// template, from which profile and when; never copied into a profile.
const templateManifest = '.gargosy-template.json';

/// The marker for each way a settings file writes a Windows path: with
/// backslashes, with forward slashes, and with doubled backslashes (TOML,
/// JSON). The doubled form is replaced first: it holds no single form.
const _forms = <(String marker, String Function(String path) spell)>[
  ('{{gargosy:profile:escaped}}', _doubled),
  ('{{gargosy:profile:slash}}', _slashed),
  ('{{gargosy:profile}}', _backslashed),
];

String _backslashed(String path) => path.replaceAll('/', r'\');
String _slashed(String path) => _backslashed(path).replaceAll(r'\', '/');
String _doubled(String path) => _backslashed(path).replaceAll(r'\', r'\\');

/// [text] with every spelling of [profileDir] (any case, as Windows compares
/// paths) replaced by its marker.
String toTemplateText(String text, String profileDir) {
  var out = text;
  for (final (marker, spell) in _forms) {
    out = _replaceIgnoringCase(out, spell(profileDir), marker);
  }
  return out;
}

final _nameChar = RegExp('[A-Za-z0-9_-]');

/// [text] with [find] (any case) replaced by [by], except where a longer
/// name starts the same (`p1` in `p12`).
String _replaceIgnoringCase(String text, String find, String by) {
  final out = StringBuffer();
  var from = 0;
  while (true) {
    final at = _indexIgnoringCase(text, find, from);
    if (at < 0) break;
    final end = at + find.length;
    if (end < text.length && _nameChar.hasMatch(text[end])) {
      out.write(text.substring(from, end));
    } else {
      out
        ..write(text.substring(from, at))
        ..write(by);
    }
    from = end;
  }
  out.write(text.substring(from));
  return out.toString();
}

/// Where [find] is in [text] from [start], any case, compared one character
/// at a time (lower-casing a whole text can change its length, `İ`).
int _indexIgnoringCase(String text, String find, int start) {
  if (find.isEmpty) return -1;
  final first = find[0].toLowerCase();
  for (var i = start; i + find.length <= text.length; i++) {
    if (text[i].toLowerCase() != first) continue;
    var j = 1;
    while (j < find.length && text[i + j].toLowerCase() == find[j].toLowerCase()) {
      j++;
    }
    if (j == find.length) return i;
  }
  return -1;
}

/// [text] with every marker replaced by [profileDir], spelled as the marker says.
String fromTemplateText(String text, String profileDir) {
  var out = text;
  for (final (marker, spell) in _forms) {
    out = out.replaceAll(marker, spell(profileDir));
  }
  return out;
}

/// Whether [text] holds a marker (only those files are rewritten on copy).
bool hasTemplateMarker(String text) => text.contains('{{gargosy:profile');
