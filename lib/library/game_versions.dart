import '../core/romm/romm_models.dart';

/// RomM's region names (its filesystem handler's list) as the three-letter
/// badges on a cover.
const _regionBadges = {
  'australia': 'AUS',
  'asia': 'ASI',
  'brazil': 'BRA',
  'canada': 'CAN',
  'china': 'CHN',
  'europe': 'EUR',
  'france': 'FRA',
  'finland': 'FIN',
  'germany': 'GER',
  'greece': 'GRE',
  'holland': 'NLD',
  'netherlands': 'NLD',
  'hong kong': 'HKG',
  'italy': 'ITA',
  'japan': 'JPN',
  'korea': 'KOR',
  'norway': 'NOR',
  'public domain': 'PD',
  'russia': 'RUS',
  'spain': 'SPA',
  'sweden': 'SWE',
  'taiwan': 'TWN',
  'usa': 'USA',
  'england': 'UK',
  'uk': 'UK',
  'world': 'WLD',
  'unlicensed': 'UNL',
};

/// [region] as a cover badge: `USA`, `EUR`, `JPN`, `WLD` …; a name Gargosy
/// doesn't know as its first three letters; null for none or Unknown.
String? regionBadge(String region) {
  final r = region.trim().toLowerCase();
  if (r.isEmpty || r == 'unknown') return null;
  return _regionBadges[r] ?? (r.length <= 3 ? r : r.substring(0, 3)).toUpperCase();
}

/// The badges for [regions], each once, in RomM's order.
List<String> regionBadges(List<String> regions) => {for (final r in regions) ?regionBadge(r)}.toList();

/// How many versions [game] has, with itself (1 when RomM lists no others).
int versionCount(Game game) => game.siblings.length + 1;

/// A version told apart from the others by its file name's tags:
/// "Ico (USA) (Rev 1)" → "(USA) (Rev 1)"; the name when it has none.
String versionLabel(String name, String fsNameNoExt) {
  final tags = RegExp(r'[\(\[][^\)\]]*[\)\]]').allMatches(fsNameNoExt).map((m) => m.group(0)!).join(' ');
  if (tags.isNotEmpty) return tags;
  return fsNameNoExt.isNotEmpty ? fsNameNoExt : name;
}

/// [game] itself as one of its versions.
GameVersion versionOf(Game game) {
  final file = game.fsName ?? '';
  final dot = file.lastIndexOf('.');
  return GameVersion(id: game.id, name: game.name, fsNameNoExt: dot > 0 ? file.substring(0, dot) : file);
}

/// [game] and its other versions, [game] first.
List<GameVersion> allVersions(Game game) => [versionOf(game), ...game.siblings];

/// On this PC, folded as RomM folds them: of a game's versions in [games]
/// (already in their order) only the first stays.
List<Game> foldVersions(List<Game> games) {
  final hidden = <String>{};
  final out = <Game>[];
  for (final g in games) {
    if (hidden.contains(g.id)) continue;
    out.add(g);
    hidden.addAll(g.siblings.map((s) => s.id));
  }
  return out;
}
