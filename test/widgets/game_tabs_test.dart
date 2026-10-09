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
    await tester.pumpWidget(testApp(AchievementsTab(game: g), overrides: [
      raProgressionProvider.overrideWith((ref) async => {
            100: {
              'earned_achievements': [
                {'id': '1', 'date': '2026-10-01 10:00:00'},
              ],
            },
          }),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('First brush'), findsOneWidget);
    expect(find.text('Sun up'), findsOneWidget);
    expect(find.textContaining('1 / 2 unlocked'), findsOneWidget);
  });

  testWidgets('a game without RetroAchievements says so', (tester) async {
    await tester.pumpWidget(testApp(AchievementsTab(game: game(1, 'Okami'))));
    expect(find.textContaining('no RetroAchievements'), findsOneWidget);
  });

  testWidgets('Notes are listed', (tester) async {
    await tester.pumpWidget(testApp(NotesTab(game: game(1, 'Okami')), overrides: [
      romNotesProvider.overrideWith((ref, id) async => [RomNote(id: 1, title: 'Boss', content: 'Use the brush on the eye', createdAt: DateTime(2026, 10, 1))]),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Boss'), findsOneWidget);
    expect(find.text('Use the brush on the eye'), findsOneWidget);
    expect(find.text('Add a note'), findsOneWidget);
  });

  testWidgets('Notes with RomM down show the error with retry', (tester) async {
    await tester.pumpWidget(testApp(NotesTab(game: game(1, 'Okami')), overrides: [
      libraryApiProvider.overrideWithValue(FakeLibraryApi(const [])..failWith = Exception('SocketException: connection refused')),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });

}
