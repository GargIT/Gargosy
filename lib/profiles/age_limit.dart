import '../core/romm/game_overview.dart';
import '../core/romm/romm_models.dart';

/// #224: a profile's age limit. Games rated above [maxAge] are hidden from
/// the profile and refused at Play; with [hideUnrated], so are games without
/// a rating Gargosy can read. [off] hides nothing.
class AgeLimit {
  const AgeLimit({this.maxAge, this.hideUnrated = false});

  /// The highest age a game may be rated for; null: no limit.
  final int? maxAge;
  final bool hideUnrated;

  static const off = AgeLimit();

  /// The limits a profile can choose, as PEGI's ages.
  static const ages = [3, 7, 12, 16, 18];

  bool get isOn => maxAge != null;

  /// Whether [game] may be shown and played.
  bool allows(Game game) => allowsAge(gameAge(game));

  /// Of [games], those it allows (all of them without a limit).
  List<Game> only(Iterable<Game> games) => isOn ? games.where(allows).toList() : games.toList();

  /// Whether a game rated for [age] (null: no rating read) may be shown.
  bool allowsAge(int? age) {
    final max = maxAge;
    if (max == null) return true;
    if (age == null) return !hideUnrated;
    return age <= max;
  }

  /// Of RomM's rating strings [values] (its `filter_values.age_ratings`),
  /// those a gallery leaves out with `age_ratings_logic=none`.
  List<String> ratingsAbove(Iterable<String> values) => [
    for (final v in values)
      if (ratingAgeOf(v) case final age? when !allowsAge(age)) v,
  ];

  /// Of [values], those a gallery keeps with `age_ratings_logic=any` (with
  /// [hideUnrated]: unrated games are in no rating, so they drop out).
  List<String> ratingsAllowed(Iterable<String> values) => [
    for (final v in values)
      if (ratingAgeOf(v) case final age? when allowsAge(age)) v,
  ];

  Map<String, dynamic> toJson() => {'max_age': maxAge, 'hide_unrated': hideUnrated};

  static AgeLimit fromJson(Object? json) {
    if (json is! Map) return off;
    final max = json['max_age'];
    if (max is! int) return off;
    // An age this build doesn't offer (a newer Gargosy's) holds at the
    // nearest stricter one, never as no limit.
    final held = ages.lastWhere((a) => a <= max, orElse: () => ages.first);
    return AgeLimit(maxAge: held, hideUnrated: json['hide_unrated'] == true);
  }

  @override
  bool operator ==(Object other) => other is AgeLimit && other.maxAge == maxAge && other.hideUnrated == hideUnrated;

  @override
  int get hashCode => Object.hash(maxAge, hideUnrated);
}

/// The highest age [game]'s ratings are for; null when it has none Gargosy
/// can read.
int? gameAge(Game game) {
  int? highest;
  for (final r in game.overview.ageRatings) {
    final age = ratingAge(r);
    if (age != null && (highest == null || age > highest)) highest = age;
  }
  return highest;
}

/// The age [rating] is for, by its board when known; null when it can't be
/// read (`RP`, an unknown board's letter).
int? ratingAge(AgeRating rating) => _ageOf(rating.category.toUpperCase(), rating.rating.toUpperCase());

/// The age of one of RomM's rating strings: `CATEGORY:RATING`, `PEGI 12`, or
/// a bare rating (`M`, `16+`).
int? ratingAgeOf(String value) {
  final text = value.trim().toUpperCase();
  final colon = text.indexOf(':');
  if (colon > 0) return _ageOf(text.substring(0, colon).trim(), text.substring(colon + 1).trim());
  final space = text.indexOf(' ');
  if (space > 0 && ageRatingBoards.containsKey(text.substring(0, space))) {
    return _ageOf(text.substring(0, space), text.substring(space + 1).trim());
  }
  return _ageOf('', text);
}

int? _ageOf(String board, String rating) {
  final r = rating.replaceAll(_boardPrefix, '').trim();
  final number = _number.firstMatch(r);
  // GRAC's 19 is adults only, as 18 elsewhere.
  if (number != null) return int.parse(number.group(1)!).clamp(0, 18);
  final byBoard = _letters[board];
  if (byBoard != null) return byBoard[r];
  // A bare letter: the strictest board that uses it.
  int? strictest;
  for (final table in _letters.values) {
    final age = table[r];
    if (age != null && (strictest == null || age > strictest)) strictest = age;
  }
  return strictest;
}

final _boardPrefix = RegExp(r'^(PEGI|USK|ESRB|CERO|ACB|GRAC)[ _]?');
final _number = RegExp(r'^(\d{1,2})\+?$');

const _letters = {
  'ESRB': {'EC': 3, 'E': 6, 'E10': 10, 'E10+': 10, 'T': 13, 'M': 17, 'AO': 18},
  'CERO': {'A': 0, 'B': 12, 'C': 15, 'D': 17, 'Z': 18},
  'ACB': {'G': 0, 'PG': 8, 'M': 15, 'MA15': 15, 'MA15+': 15, 'R18': 18, 'R18+': 18, 'X18': 18, 'X18+': 18, 'RC': 18},
  'CLASS_IND': {'L': 0, 'AL': 0},
  'GRAC': {'ALL': 0},
  'PEGI': <String, int>{},
  'USK': <String, int>{},
};
