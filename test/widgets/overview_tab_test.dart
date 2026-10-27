import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/game/overview_tab.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  final metroid = Game.fromJson({
    ...gameJson(1, 'Super Metroid'),
    'metadatum': {
      'player_count': '1',
      'age_ratings': ['PEGI:7'],
    },
    'igdb_metadata': {
      'remasters': [
        {'id': 1001, 'name': 'Super Metroid (GBA)', 'cover_url': ''},
        {'id': 1002, 'name': 'Metroid Prime Remastered', 'cover_url': ''},
      ],
    },
    'hltb_metadata': {'main_story': 25200, 'completionist': 43200},
  });

  testWidgets('Overview (#179): players, age rating, How long to beat, related and similar games', (tester) async {
    await setDesktopSize(tester);
    final api = FakeLibraryApi(const [])
      ..byIgdb = {1001: game(2, 'Super Metroid GBA')}
      ..similarGames = {
        '1': [game(3, 'Metroid Fusion')],
      };
    await tester.pumpWidget(
      testApp(OverviewTab(game: metroid), overrides: [libraryApiProvider.overrideWithValue(api)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('PLAYERS'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('PEGI 7'), findsOneWidget);
    expect(find.text('HOW LONG TO BEAT'), findsOneWidget);
    expect(find.text('7 h'), findsOneWidget);
    expect(find.text('12 h'), findsOneWidget);
    expect(find.text('Remasters'), findsOneWidget);
    expect(find.text('Super Metroid GBA'), findsWidgets, reason: "the library's game");
    expect(find.text('Metroid Prime Remastered'), findsWidgets);
    expect(find.text('NOT ON ROMM'), findsOneWidget);
    expect(find.text('Similar games in your library'), findsOneWidget);
    expect(find.text('Metroid Fusion'), findsWidgets);
  });

  testWidgets('without facts, times or related games none of it shows', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(
      testApp(
        OverviewTab(game: game(1, 'Okami')),
        overrides: [libraryApiProvider.overrideWithValue(FakeLibraryApi(const []))],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PLAYERS'), findsNothing);
    expect(find.text('HOW LONG TO BEAT'), findsNothing);
    expect(find.text('Similar games in your library'), findsNothing);
  });
}
