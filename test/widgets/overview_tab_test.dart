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
    'summary': 'Samus returns to Zebes.',
    'metadatum': {
      'player_count': '1',
      'age_ratings': ['PEGI:7'],
    },
    'hltb_metadata': {'main_story': 25200, 'completionist': 43200},
  });

  testWidgets('Overview (#179): facts, How long to beat, the description, similar games', (tester) async {
    await setDesktopSize(tester);
    final api = FakeLibraryApi(const [])
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
    expect(find.text('SIMILAR GAMES IN YOUR LIBRARY'), findsOneWidget);
    expect(find.text('Metroid Fusion'), findsWidgets);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(find.text('PLAYERS')), lessThan(top(find.text('HOW LONG TO BEAT'))));
    expect(top(find.text('HOW LONG TO BEAT')), lessThan(top(find.text('Samus returns to Zebes.'))));
    expect(top(find.text('Samus returns to Zebes.')), lessThan(top(find.text('SIMILAR GAMES IN YOUR LIBRARY'))));
  });

  testWidgets('without facts, times or similar games none of it shows', (tester) async {
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
    expect(find.text('SIMILAR GAMES IN YOUR LIBRARY'), findsNothing);
  });
}
