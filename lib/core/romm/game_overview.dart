/// What the game page's Overview shows beyond the summary (#179): the age
/// ratings and HowLongToBeat's times, read from a RomM game and kept in the
/// offline snapshot ([toJson] / [fromJson]).
class GameOverview {
  const GameOverview({this.ageRatings = const [], this.hltb});

  static const empty = GameOverview();

  final List<AgeRating> ageRatings;
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
    ageRatings: [
      for (final r in json['age_ratings'] is List ? json['age_ratings'] as List : const []) ?AgeRating.fromJson(r),
    ],
    hltb: HowLongToBeat.fromJson(json['hltb']),
  );

  Map<String, dynamic> toJson() => {
    'age_ratings': [for (final r in ageRatings) r.toJson()],
    'hltb': hltb?.toJson(),
  };
}

/// One age rating: its board ([category], empty when unknown), the
/// [rating] and the board's icon on IGDB ([iconUrl]), as RomM's page shows it.
class AgeRating {
  const AgeRating(this.category, this.rating, {this.iconUrl});

  final String category;
  final String rating;
  final String? iconUrl;

  /// As it reads: `ESRB T`, `PEGI 12`.
  String get label => category.isEmpty ? rating : '$category $rating';

  /// What [toJson] wrote; a snapshot from before icons held the [label].
  static AgeRating? fromJson(Object? json) {
    if (json is Map && json['rating'] != null) {
      final category = '${json['category'] ?? ''}';
      final rating = '${json['rating']}';
      return AgeRating(category, rating, iconUrl: json['icon'] is String ? json['icon'] as String : null);
    }
    if (json is String && json.trim().isNotEmpty) {
      final words = json.trim().split(' ');
      return words.length > 1 && ageRatingBoards.containsKey(words.first)
          ? AgeRating(
              words.first,
              words.skip(1).join(' '),
              iconUrl: igdbRatingIcon(words.first, words.skip(1).join(' ')),
            )
          : AgeRating('', json.trim());
    }
    return null;
  }

  Map<String, dynamic> toJson() => {'category': category, 'rating': rating, 'icon': iconUrl};

  @override
  bool operator ==(Object other) =>
      other is AgeRating && other.category == category && other.rating == rating && other.iconUrl == iconUrl;

  @override
  int get hashCode => Object.hash(category, rating, iconUrl);

  @override
  String toString() => label;
}

/// The rating boards and their folder in IGDB's rating icons.
const ageRatingBoards = {
  'ESRB': 'esrb',
  'PEGI': 'pegi',
  'CERO': 'cero',
  'USK': 'usk',
  'GRAC': 'grac',
  'CLASS_IND': 'class_ind',
  'ACB': 'acb',
};

/// IGDB's icon for a board's rating, by the same rule as RomM's page
/// (`PEGI`, `16+` → `…/pegi/pegi_16.png`); null for a board it doesn't know.
String? igdbRatingIcon(String category, String rating) {
  final folder = ageRatingBoards[category];
  if (folder == null || rating.isEmpty) return null;
  return 'https://www.igdb.com/icons/rating_icons/$folder/${folder}_${rating.toLowerCase().replaceFirst('+', '')}.png';
}

/// RomM's `metadatum.age_ratings` as ratings: `CATEGORY:RATING` (typed by
/// hand) as written; a bare rating takes its category, and IGDB's icon, from
/// a provider's list in [providers] (`{rating, category, rating_cover_url}`
/// maps) when one has it. The icon is IGDB's by RomM's rule when no provider
/// gave one.
List<AgeRating> ageRatingLabels(Object? ratings, List<Object?> providers) {
  final known = <String, (String, String?)>{};
  for (final list in providers) {
    for (final r in list is List ? list : const []) {
      if (r is Map && r['rating'] != null && r['category'] is String) {
        final cover = r['rating_cover_url'];
        known.putIfAbsent(
          '${r['rating']}'.trim(),
          () => ((r['category'] as String).trim(), cover is String && cover.isNotEmpty ? _https(cover) : null),
        );
      }
    }
  }
  final out = <AgeRating>[];
  for (final entry in ratings is List ? ratings : const []) {
    final text = '$entry'.trim();
    if (text.isEmpty) continue;
    final colon = text.indexOf(':');
    final (category, rating, icon) = colon > 0
        ? (text.substring(0, colon).trim(), text.substring(colon + 1).trim(), null)
        : (known[text]?.$1 ?? '', text, known[text]?.$2);
    final r = AgeRating(category, rating, iconUrl: icon ?? igdbRatingIcon(category, rating));
    if (!out.contains(r)) out.add(r);
  }
  return out;
}

String _https(String url) => url.startsWith('//') ? 'https:$url' : url;

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
