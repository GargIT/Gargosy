import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/providers/library_providers.dart';
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

  testWidgets('Overview (#179): the description, facts, How long to beat, similar games', (tester) async {
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
    expect(find.byTooltip('PEGI 7'), findsOneWidget);
    expect(find.text('HOW LONG TO BEAT'), findsOneWidget);
    expect(find.text('7 h'), findsOneWidget);
    expect(find.text('12 h'), findsOneWidget);
    expect(find.text('SIMILAR GAMES IN YOUR LIBRARY'), findsOneWidget);
    expect(find.text('Metroid Fusion'), findsWidgets);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(find.text('Samus returns to Zebes.')), lessThan(top(find.text('PLAYERS'))));
    expect(top(find.text('PLAYERS')), lessThan(top(find.text('HOW LONG TO BEAT'))));
    expect(top(find.text('HOW LONG TO BEAT')), lessThan(top(find.text('SIMILAR GAMES IN YOUR LIBRARY'))));
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

  testWidgets("the player's own screenshots (#233) come first in the strip, before RomM's", (tester) async {
    await setDesktopSize(tester);
    final g = Game.fromJson({
      ...gameJson(1, 'Okami'),
      'merged_screenshots': ['http://romm/assets/romm/resources/roms/1/1/screenshots/0.jpg'],
      'user_screenshots': [
        {'download_path': '/api/raw/assets/users/1/screenshots/mine.png'},
      ],
    });
    await tester.pumpWidget(
      testApp(
        OverviewTab(game: g),
        overrides: [
          libraryApiProvider.overrideWithValue(FakeLibraryApi(const [])),
          userScreenshotProvider.overrideWith((ref, path) async => null),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Screenshots'), findsOneWidget);
    final own = find.byKey(const ValueKey('own-shot:/api/raw/assets/users/1/screenshots/mine.png'));
    expect(own, findsOneWidget);
    final romm = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key! as ValueKey).value}'.contains('0.jpg'));
    expect(romm, findsOneWidget);
    expect(tester.getTopLeft(own).dx, lessThan(tester.getTopLeft(romm).dx));
  });
}
