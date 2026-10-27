import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/game_overview.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/ui/screens/game/overview_facts.dart';

import '../helpers/fake_dio_adapter.dart';
import '../helpers/game_fixtures.dart';

void main() {
  final json = {
    ...gameJson(1, 'Super Metroid'),
    'metadatum': {
      'player_count': '1',
      'age_ratings': ['PEGI:7', 'E', 'T', 'PEGI:7', 'A'],
    },
    'igdb_metadata': {
      'age_ratings': [
        {'rating': 'E', 'category': 'ESRB', 'rating_cover_url': '//images.igdb.com/e.png'},
      ],
      'remasters': [
        {
          'id': 1001,
          'name': 'Super Metroid (GBA)',
          'slug': 'x',
          'type': 'remaster',
          'cover_url': '//images.igdb.com/1.jpg',
        },
      ],
      'ports': <Object>[],
      'dlcs': [
        {'id': 'bad', 'name': 'No id'},
      ],
    },
    'ss_metadata': {
      'age_ratings': [
        {'rating': 'T', 'category': 'USK'},
      ],
    },
    'hltb_metadata': {'main_story': 25200, 'main_plus_extra': 34200, 'completionist': 0, 'all_styles': 2700},
  };

  test("RomM's age ratings read as category and rating, once each", () {
    expect(Game.fromJson(json).overview.ageRatings, ['PEGI 7', 'ESRB E', 'USK T', 'A']);
  });

  test("HowLongToBeat's times there are, and none when RomM has none", () {
    final hltb = Game.fromJson(json).overview.hltb!;
    expect(hltb.entries, [('Main story', 25200), ('Main + extra', 34200), ('All styles', 2700)]);
    expect(HowLongToBeat.fromJson({'main_story': 0}), isNull);
    expect(HowLongToBeat.fromJson(null), isNull);
  });

  test('a time reads in minutes under an hour, else hours to the half hour', () {
    expect(hltbTime(2700), '45 min');
    expect(hltbTime(25200), '7 h');
    expect(hltbTime(34200), '9.5 h');
    expect(hltbTime(26000), '7 h');
  });

  test("IGDB's related games by kind, the empty and broken ones left out", () {
    final related = Game.fromJson(json).overview.related;
    expect(related.keys, [RelatedKind.remasters]);
    expect(related[RelatedKind.remasters]!.single.name, 'Super Metroid (GBA)');
    expect(related[RelatedKind.remasters]!.single.coverUrl, 'https://images.igdb.com/1.jpg');
  });

  test('the overview comes back from the offline snapshot', () {
    final again = Game.fromJson(Game.fromJson(json).toJson()).overview;
    expect(again.ageRatings, ['PEGI 7', 'ESRB E', 'USK T', 'A']);
    expect(again.hltb!.mainPlusExtra, 34200);
    expect(again.related[RelatedKind.remasters]!.single.igdbId, 1001);
  });

  test("similar games from RomM's index; an IGDB id's game in the library; none on a 404", () async {
    RommLibraryApi api(FakeDioAdapter a) => RommLibraryApi(fakeDio(a), () => Options());
    final a = FakeDioAdapter(
      (r) => r.path.endsWith('/similar')
          ? (
              status: 200,
              body: [
                {'rom': gameJson(3, 'Metroid Fusion'), 'score': 0.7, 'reasons': []},
              ],
            )
          : (status: 200, body: gameJson(2, 'Super Metroid GBA')),
    );
    expect([for (final g in await api(a).similar('1')) g.name], ['Metroid Fusion']);
    expect((await api(a).byIgdbId(1001))?.name, 'Super Metroid GBA');
    expect(a.requests.last.queryParameters, {'igdb_id': 1001});
    final missing = FakeDioAdapter((_) => (status: 404, body: <String, dynamic>{}));
    expect(await api(missing).similar('1'), isEmpty);
    expect(await api(missing).byIgdbId(1), isNull);
  });

  test("the players' icon follows the largest number", () {
    expect(OverviewFacts.playersIcon('1'), Icons.person_outline);
    expect(OverviewFacts.playersIcon('1-2'), Icons.people_outline);
    expect(OverviewFacts.playersIcon('Up to 4 players'), Icons.groups_outlined);
    expect(OverviewFacts.playersIcon('Massively Multiplayer'), Icons.groups_outlined);
  });
}
