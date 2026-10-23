import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/pages/collections_page.dart';
import 'package:gargosy/ui/pages/search_page.dart';
import 'package:gargosy/ui/screens/collection/collection_screen.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  testWidgets('collections: favourites first, then by name; A opens a gallery', (tester) async {
    await setDesktopSize(tester);
    final api = FakeLibraryApi([game(1, 'Okami')]);
    await tester.pumpWidget(
      testApp(
        const CollectionsPage(),
        overrides: [
          collectionsProvider.overrideWith(
            (ref) async => const [
              RommCollection(id: 2, name: 'RPGs', romCount: 12, userId: 7),
              RommCollection(id: 1, name: 'Favorites', isFavorite: true, romCount: 3, userId: 7),
              RommCollection(id: 3, name: 'Arcade', romCount: 5, userId: 7),
            ],
          ),
          libraryApiProvider.overrideWithValue(api),
          favouriteIdsProvider.overrideWithValue(const {}),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final names = tester.widgetList<Text>(find.byKey(const ValueKey('collection-name'))).map((t) => t.data).toList();
    expect(names, ['Favourites', 'Arcade', 'RPGs']);
    await press(tester, GameAction.confirm);
    expect(find.byType(CollectionScreen), findsOneWidget);
    expect(api.queries.last.$1.favourites, isTrue);
  });

  testWidgets('search: type on the keyboard, results show under it', (tester) async {
    await setDesktopSize(tester);
    final api = FakeLibraryApi([game(1, 'Okami'), game(2, 'Ico'), game(3, 'Okamiden')]);
    await tester.pumpWidget(
      testApp(
        const SearchPage(),
        overrides: [libraryApiProvider.overrideWithValue(api), favouriteIdsProvider.overrideWithValue(const {})],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Search your library'), findsOneWidget);
    await press(tester, GameAction.confirm); // opens the keyboard
    for (final ch in 'okami'.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey.findKeyByKeyId(ch.codeUnitAt(0))!, character: ch);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.search, 'okami');
    expect(find.text('Okami'), findsWidgets);
    expect(find.text('Okamiden'), findsWidgets);
    expect(find.text('Ico'), findsNothing);
  });
}
