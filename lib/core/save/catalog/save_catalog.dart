// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:flutter/foundation.dart';

import 'save_entry.dart';

/// Versions of one RomM save (same slot and tag), newest first.
@immutable
class RommSaveGroup {
  const RommSaveGroup({required this.slot, required this.tag, required this.newest, required this.older});
  final String slot;
  final String tag;
  final SaveEntry newest;
  final List<SaveEntry> older;
}

/// One other player's shared saves of the game (#92), grouped as RomM's.
@immutable
class PlayerSaves {
  const PlayerSaves({required this.owner, required this.groups});
  final SaveOwner owner;
  final List<RommSaveGroup> groups;
}

/// Every save of one game, as the play screen and the Saves tab list them.
@immutable
class SaveCatalog {
  const SaveCatalog({
    required this.thisPc,
    required this.backups,
    required this.romm,
    required this.rommOffline,
    this.others = const [],
  });

  /// One row per installed emulator that has a save for the game, newest first.
  final List<SaveEntry> thisPc;

  /// Local backups, newest first.
  final List<SaveEntry> backups;

  /// RomM saves, the group with the newest save first.
  final List<RommSaveGroup> romm;

  /// RomM couldn't be listed (offline or failing).
  final bool rommOffline;

  /// Other players' shared saves, the player with the newest first. Never
  /// in [all]: not the player's own saves, so never counted or synced.
  final List<PlayerSaves> others;

  List<SaveEntry> get all => [
    ...thisPc,
    ...backups,
    for (final g in romm) ...[g.newest, ...g.older],
  ];
}

int _newestFirst(SaveEntry a, SaveEntry b) => b.savedAt.compareTo(a.savedAt);

List<RommSaveGroup> _groups(Iterable<SaveEntry> saves) {
  final groups = <String, List<SaveEntry>>{};
  for (final e in saves) {
    groups.putIfAbsent(e.groupKey, () => []).add(e);
  }
  return [
    for (final versions in groups.values)
      () {
        final sorted = [...versions]..sort(_newestFirst);
        return RommSaveGroup(
          slot: sorted.first.slot ?? '',
          tag: sorted.first.tag ?? '',
          newest: sorted.first,
          older: sorted.sublist(1),
        );
      }(),
  ]..sort((a, b) => _newestFirst(a.newest, b.newest));
}

/// [romm] null: RomM couldn't be listed. [others]: other players' shared
/// saves (each with its [SaveEntry.owner]).
SaveCatalog buildSaveCatalog({
  required List<SaveEntry> local,
  required List<SaveEntry> backups,
  required List<SaveEntry>? romm,
  List<SaveEntry> others = const [],
}) {
  final byOwner = <SaveOwner, List<SaveEntry>>{};
  for (final e in others) {
    if (e.owner case final owner?) byOwner.putIfAbsent(owner, () => []).add(e);
  }
  return SaveCatalog(
    thisPc: [...local]..sort(_newestFirst),
    backups: [...backups]..sort(_newestFirst),
    romm: _groups(romm ?? const []),
    rommOffline: romm == null,
    others: [for (final e in byOwner.entries) PlayerSaves(owner: e.key, groups: _groups(e.value))]
      ..sort((a, b) => _newestFirst(a.groups.first.newest, b.groups.first.newest)),
  );
}
