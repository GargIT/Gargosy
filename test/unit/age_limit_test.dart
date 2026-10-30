import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/age_limit.dart';
import 'package:gargosy/profiles/profile.dart';

import '../helpers/game_fixtures.dart';

/// A game RomM rated [ratings] (`BOARD:RATING`, as in its metadatum).
Game _rated(List<String> ratings) => Game.fromJson({
  ...gameJson(1, 'G'),
  'metadatum': {'age_ratings': ratings},
});

void main() {
  test("each board's ratings as ages", () {
    expect(ratingAgeOf('PEGI 12'), 12);
    expect(ratingAgeOf('PEGI:16'), 16);
    expect(ratingAgeOf('16+'), 16);
    expect(ratingAgeOf('ESRB:E10+'), 10);
    expect(ratingAgeOf('T'), 13);
    expect(ratingAgeOf('M'), 17, reason: "ESRB's M is stricter than ACB's");
    expect(ratingAgeOf('ACB:M'), 15);
    expect(ratingAgeOf('CERO:Z'), 18);
    expect(ratingAgeOf('A'), 0);
    expect(ratingAgeOf('GRAC:19'), 18);
    expect(ratingAgeOf('RP'), isNull);
    expect(ratingAgeOf('Mature'), isNull);
  });

  test("a game's age is its highest rating's", () {
    expect(gameAge(_rated(const ['PEGI:7', 'ESRB:T'])), 13);
    expect(gameAge(_rated(const [])), isNull);
  });

  test('allows: up to the limit; unrated shown unless hidden; off allows all', () {
    const twelve = AgeLimit(maxAge: 12);
    expect(twelve.allows(_rated(const ['PEGI:12'])), isTrue);
    expect(twelve.allows(_rated(const ['PEGI:7', 'ESRB:M'])), isFalse);
    expect(twelve.allows(_rated(const [])), isTrue);
    expect(const AgeLimit(maxAge: 12, hideUnrated: true).allows(_rated(const [])), isFalse);
    expect(AgeLimit.off.allows(_rated(const ['PEGI:18'])), isTrue);
    expect(const AgeLimit(hideUnrated: true).allows(_rated(const [])), isTrue, reason: 'no limit, nothing hidden');
  });

  test("RomM's filter: the ratings above the limit, and those allowed", () {
    const values = ['3', '7', '12', '16', '18', 'E', 'T', 'M', 'RP'];
    expect(const AgeLimit(maxAge: 12).ratingsAbove(values), ['16', '18', 'T', 'M']);
    expect(const AgeLimit(maxAge: 12).ratingsAllowed(values), ['3', '7', '12', 'E']);
  });

  test('kept in profile.json; an age it does not offer reads as off', () {
    const l = AgeLimit(maxAge: 7, hideUnrated: true);
    expect(AgeLimit.fromJson(l.toJson()), l);
    expect(AgeLimit.fromJson({'max_age': 9}), AgeLimit.off);
    expect(AgeLimit.fromJson(null), AgeLimit.off);
  });

  test("a profile keeps its limit in profile.json; one without it has none", () {
    final p = Profile(
      id: 'aaa',
      name: 'Kid',
      colorIndex: 0,
      serverUrl: 's',
      rommUserId: 1,
      rommUsername: 'kid',
      createdAt: DateTime(2026),
    );
    expect(p.toJson().containsKey('ageLimit'), isFalse);
    final limited = p.copyWith(ageLimit: const AgeLimit(maxAge: 12, hideUnrated: true));
    expect(Profile.fromJson(limited.toJson()).ageLimit, const AgeLimit(maxAge: 12, hideUnrated: true));
    expect(Profile.fromJson(p.toJson()).ageLimit, AgeLimit.off);
  });
}
