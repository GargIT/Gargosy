/// What the game page's Overview shows beyond the summary (#179): the age
/// ratings and HowLongToBeat's times, read from a RomM game and kept in the
/// offline snapshot ([toJson] / [fromJson]).
class GameOverview {
  const GameOverview({this.ageRatings = const [], this.hltb});

  static const empty = GameOverview();

  /// Each rating as it reads: `ESRB T`, `PEGI 12`.
  final List<String> ageRatings;
  final HowLongToBeat? hltb;

  /// From RomM's game: `metadatum.age_ratings` (matched with IGDB's and
  /// ScreenScraper's for the category, as RomM's own page does) and
  /// `hltb_metadata`.
  factory GameOverview.fromRomm(Map<String, dynamic> json) {
    final igdb = json['igdb_metadata'] is Map ? json['igdb_metadata'] as Map : const {};
    final ss = json['ss_metadata'] is Map ? json['ss_metadata'] as Map : const {};
    final metadatum = json['metadatum'] is Map ? json['metadatum'] as Map : const {};
    return GameOverview(
      ageRatings: ageRatingLabels(metadatum['age_ratings'], [igdb['age_ratings'], ss['age_ratings']]),
      hltb: HowLongToBeat.fromJson(json['hltb_metadata']),
    );
  }

  /// What [toJson] wrote.
  factory GameOverview.fromJson(Map<String, dynamic> json) => GameOverview(
    ageRatings: [for (final r in json['age_ratings'] is List ? json['age_ratings'] as List : const []) '$r'],
    hltb: HowLongToBeat.fromJson(json['hltb']),
  );

  Map<String, dynamic> toJson() => {'age_ratings': ageRatings, 'hltb': hltb?.toJson()};
}

/// RomM's `metadatum.age_ratings` as they read: `CATEGORY:RATING` (typed by
/// hand) becomes `CATEGORY RATING`; a bare rating takes its category from
/// a provider's list in [providers] (`{rating, category}` maps) when one
/// has it.
List<String> ageRatingLabels(Object? ratings, List<Object?> providers) {
  final categories = <String, String>{};
  for (final list in providers) {
    for (final r in list is List ? list : const []) {
      if (r is Map && r['rating'] != null && r['category'] is String) {
        categories.putIfAbsent('${r['rating']}'.trim(), () => (r['category'] as String).trim());
      }
    }
  }
  final labels = <String>[];
  for (final entry in ratings is List ? ratings : const []) {
    final text = '$entry'.trim();
    if (text.isEmpty) continue;
    final colon = text.indexOf(':');
    final label = colon > 0
        ? '${text.substring(0, colon).trim()} ${text.substring(colon + 1).trim()}'
        : [?categories[text], text].join(' ');
    if (!labels.contains(label)) labels.add(label);
  }
  return labels;
}

/// HowLongToBeat's times for a game, in seconds.
class HowLongToBeat {
  const HowLongToBeat({this.mainStory, this.mainPlusExtra, this.completionist, this.allStyles});

  final int? mainStory;
  final int? mainPlusExtra;
  final int? completionist;
  final int? allStyles;

  /// Null when RomM has none of the times.
  static HowLongToBeat? fromJson(Object? json) {
    if (json is! Map) return null;
    int? seconds(String key) => json[key] is num && (json[key] as num) > 0 ? (json[key] as num).round() : null;
    final hltb = HowLongToBeat(
      mainStory: seconds('main_story'),
      mainPlusExtra: seconds('main_plus_extra'),
      completionist: seconds('completionist'),
      allStyles: seconds('all_styles'),
    );
    return hltb.entries.isEmpty ? null : hltb;
  }

  /// The times there are, as RomM's strip lists them.
  List<(String, int)> get entries => [
    if (mainStory case final s?) ('Main story', s),
    if (mainPlusExtra case final s?) ('Main + extra', s),
    if (completionist case final s?) ('Completionist', s),
    if (allStyles case final s?) ('All styles', s),
  ];

  Map<String, dynamic> toJson() => {
    'main_story': mainStory,
    'main_plus_extra': mainPlusExtra,
    'completionist': completionist,
    'all_styles': allStyles,
  };
}

/// A HowLongToBeat time as RomM shows it: minutes under an hour, else hours
/// to the half hour (`45 min`, `7 h`, `9.5 h`).
String hltbTime(int seconds) {
  if (seconds < 3600) return '${(seconds / 60).round()} min';
  final halves = (seconds / 1800).round();
  return halves.isEven ? '${halves ~/ 2} h' : '${halves ~/ 2}.5 h';
}
