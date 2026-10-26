import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/game/achievements_tab.dart';
import 'package:gargosy/ui/screens/game/notes_tab.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  testWidgets('Achievements show unlocks from RomM progress', (tester) async {
    final g = Game.fromJson({
      ...gameJson(1, 'Okami'),
      'ra_id': 100,
      'merged_ra_metadata': {
        'achievements': [
          {'ra_id': 1, 'title': 'First brush', 'description': 'Use the brush', 'points': 5, 'badge_id': '1'},
          {'ra_id': 2, 'title': 'Sun up', 'description': 'Restore the sun', 'points': 10, 'badge_id': '2'},
        ],
      },
    });
    await tester.pumpWidget(
      testApp(
        AchievementsTab(game: g),
        overrides: [
          raProgressionProvider.overrideWith(
            (ref) async => {
              100: {
                'earned_achievements': [
                  {'id': '1', 'date': '2026-10-01 10:00:00'},
                ],
              },
            },
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('First brush'), findsOneWidget);
    expect(find.text('Sun up'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('5 / 15'), findsOneWidget, reason: 'points earned of all');
  });

  group('filters and columns (#174)', () {
    final g = Game.fromJson({
      ...gameJson(1, 'Okami'),
      'ra_id': 100,
      'merged_ra_metadata': {
        'achievements': [
          {'ra_id': 1, 'title': 'First brush', 'points': 5, 'badge_id': '1', 'type': 'progression'},
          {'ra_id': 2, 'title': 'Sun up', 'points': 10, 'badge_id': '2', 'type': 'win_condition'},
          {'ra_id': 3, 'title': 'Lost dog', 'points': 25, 'badge_id': '3', 'type': 'missable'},
          {'ra_id': 4, 'title': 'Fisher', 'points': 3, 'badge_id': '4'},
        ],
      },
    });
    final progress = raProgressionProvider.overrideWith(
      (ref) async => {
        100: {
          'earned_achievements': [
            {'id': '1', 'date': '2026-10-01 10:00:00'},
            {'id': '3', 'date': '2026-10-02 10:00:00'},
          ],
        },
      },
    );

    testWidgets('the summary counts progression and missable ones', (tester) async {
      await tester.pumpWidget(testApp(AchievementsTab(game: g), overrides: [progress]));
      await tester.pumpAndSettle();
      expect(find.text('2 / 4'), findsOneWidget);
      expect(find.text('30 / 43'), findsOneWidget);
      expect(find.text('PROGRESSION'), findsNWidgets(2), reason: 'the stat and the tag');
      expect(find.text('MISSABLE'), findsNWidgets(2));
      expect(find.text('WIN CONDITION'), findsOneWidget, reason: 'the type tag');
    });

    testWidgets('a type filter and Earned / Locked narrow the list', (tester) async {
      await tester.pumpWidget(testApp(AchievementsTab(game: g), overrides: [progress]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Missable'));
      await tester.pumpAndSettle();
      expect(find.text('Lost dog'), findsOneWidget);
      expect(find.text('First brush'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.tap(find.text('⊘ Locked'));
      await tester.pumpAndSettle();
      expect(find.text('Sun up'), findsOneWidget);
      expect(find.text('Fisher'), findsOneWidget);
      expect(find.text('First brush'), findsNothing);

      await tester.tap(find.text('✓ Earned'));
      await tester.pumpAndSettle();
      expect(find.text('First brush'), findsOneWidget);
      expect(find.text('Sun up'), findsNothing);

      await tester.tap(find.text('Win condition'));
      await tester.pumpAndSettle();
      expect(find.text('No achievements match these filters.'), findsOneWidget);

      await tester.tap(find.text('✓ Earned'));
      await tester.pumpAndSettle();
      expect(find.text('Sun up'), findsOneWidget, reason: 'tapped again: earned or not');
    });

    test('one column per 380 px, 1 to 4', () {
      expect(achievementColumns(300), 1);
      expect(achievementColumns(800), 2);
      expect(achievementColumns(1200), 3);
      expect(achievementColumns(3000), 4);
    });
  });

  testWidgets('a game without RetroAchievements says so', (tester) async {
    await tester.pumpWidget(testApp(AchievementsTab(game: game(1, 'Okami'))));
    expect(find.textContaining('no RetroAchievements'), findsOneWidget);
  });

  testWidgets('Notes are listed', (tester) async {
    await tester.pumpWidget(
      testApp(
        NotesTab(game: game(1, 'Okami')),
        overrides: [
          romNotesProvider.overrideWith(
            (ref, id) async => [
              RomNote(id: 1, title: 'Boss', content: 'Use the brush on the eye', createdAt: DateTime(2026, 10, 1)),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Boss'), findsOneWidget);
    expect(find.text('Use the brush on the eye'), findsOneWidget);
    expect(find.text('Add a note'), findsOneWidget);
  });

  testWidgets('Notes with RomM down show the error with retry', (tester) async {
    await tester.pumpWidget(
      testApp(
        NotesTab(game: game(1, 'Okami')),
        overrides: [
          libraryApiProvider.overrideWithValue(
            FakeLibraryApi(const [])..failWith = Exception('SocketException: connection refused'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });
}
