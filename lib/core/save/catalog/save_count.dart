import 'save_entry.dart';

/// How many different saves [entries] hold: copies of one save (on this PC,
/// on RomM, in a backup) count once. Two rows are the same save when they
/// share a `content_hash`, or a save on this PC was last synced with that
/// RomM save. A row with nothing to compare by counts on its own.
int distinctSaveCount(Iterable<SaveEntry> entries) {
  final parent = <int>[];
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  final owner = <String, int>{};
  for (final e in entries) {
    final i = parent.length;
    parent.add(i);
    for (final key in _keys(e)) {
      final other = owner[key];
      if (other == null) {
        owner[key] = i;
      } else {
        parent[find(i)] = find(other);
      }
    }
  }
  return {for (var i = 0; i < parent.length; i++) find(i)}.length;
}

Iterable<String> _keys(SaveEntry e) sync* {
  for (final h in e.contentHashes) {
    yield 'hash:$h';
  }
  final save = e.rommSave;
  if (save != null) {
    final hash = save['content_hash']?.toString();
    if (hash != null && hash.isNotEmpty) yield 'hash:$hash';
    final id = save['id']?.toString();
    if (id != null) yield 'romm:$id';
  }
  if (e.sameAsRommId case final id?) yield 'romm:$id';
}
