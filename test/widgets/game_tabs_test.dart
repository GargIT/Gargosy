import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/backup_entry.dart';
import 'package:gargosy/library/upload_queue.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/romm/romm_state.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/game/achievements_tab.dart';
import 'package:gargosy/ui/screens/game/notes_tab.dart';
import 'package:gargosy/ui/screens/game/save_data_tab.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  testWidgets('Save data lists RomM saves and states', (tester) async {
    final g = game(1, 'Okami');
    await tester.pumpWidget(testApp(SaveDataTab(game: g), overrides: [
      romSavesProvider.overrideWith((ref, id) async => [
            {'id': 3, 'file_name': 'okami.ps2', 'emulator': 'pcsx2', 'updated_at': '2026-10-01T10:00:00Z', 'file_size_bytes': 8388608},
          ]),
      romStatesProvider.overrideWith((ref, id) async => [
            RommState.fromJson({'id': 9, 'file_name': 'okami.p2s', 'emulator': 'pcsx2', 'updated_at': '2026-10-02T10:00:00Z'}),
          ]),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('okami.ps2'), findsOneWidget);
    expect(find.textContaining('8.0 MB'), findsOneWidget);
    expect(find.text('okami.p2s'), findsOneWidget);
  });

  testWidgets('Save data says so when there are none, and shows errors with retry', (tester) async {
    final g = game(1, 'Okami');
    await tester.pumpWidget(testApp(SaveDataTab(game: g), overrides: [
      romSavesProvider.overrideWith((ref, id) async => throw StateError('RomM did not answer')),
      romStatesProvider.overrideWith((ref, id) async => const []),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('No states'), findsOneWidget);
  });

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

  testWidgets('a save waiting to upload shows on Save Data', (tester) async {
    final g = game(7, 'Burnout 3');
    await tester.pumpWidget(testApp(SaveDataTab(game: g), overrides: [
      romSavesProvider.overrideWith((ref, id) async => const []),
      romStatesProvider.overrideWith((ref, id) async => const []),
      uploadsWaitingProvider.overrideWith((ref, id) => [BackupEntry(timestamp: DateTime(2026, 10, 9, 21), md5Hash: 'h', localZipPath: 'z.zip')]),
    ]));
    await tester.pumpAndSettle();
    expect(find.textContaining('Waiting to upload'), findsOneWidget);
  });
}
