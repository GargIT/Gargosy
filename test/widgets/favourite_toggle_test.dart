import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/gallery_screen.dart';
import 'package:gargosy/ui/screens/game/notes_tab.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  final games = [game(1, 'Okami'), game(2, 'Ico')];

  Future<FakeLibraryApi> pumpGallery(WidgetTester tester, FakeLibraryApi api) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(
      testApp(
        const GalleryScreen(title: 'All', query: GalleryQuery()),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          favouriteIdsProvider.overrideWithValue(const {}),
          rommUserIdProvider.overrideWithValue(7),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('a favourite that RomM refuses says so', (tester) async {
    final api = await pumpGallery(tester, FakeLibraryApi(games));
    api.failWith = Exception('SocketException: connection refused');
    await press(tester, GameAction.favorite);
    expect(find.textContaining("Couldn't update favourites"), findsOneWidget);
  });

  testWidgets('pressing Y twice quickly sends one change', (tester) async {
    final api = await pumpGallery(tester, FakeLibraryApi(games)..favouriteDelay = Completer<void>());
    await press(tester, GameAction.favorite);
    await press(tester, GameAction.favorite);
    expect(api.favouriteCalls, ['1']);
    api.favouriteDelay!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a note RomM refuses to save says so', (tester) async {
    final api = FakeLibraryApi(const []);
    await tester.pumpWidget(
      testApp(NotesTab(game: game(1, 'Okami')), overrides: [libraryApiProvider.overrideWithValue(api)]),
    );
    await tester.pumpAndSettle();
    api.failWith = Exception('SocketException: connection refused');
    await tester.tap(find.text('Add a note'));
    await tester.pumpAndSettle();
    for (final step in ['Title', 'Body']) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(step, isNotEmpty);
    }
    expect(find.textContaining("Couldn't save the note"), findsOneWidget);
  });
}
