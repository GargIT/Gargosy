import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/pages/collections_page.dart';
import 'package:gargosy/ui/screens/game/game_screen.dart';
import 'package:gargosy/ui/theme/tokens.dart';
import 'package:gargosy/ui/screens/collection/collection_screen.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  const me = 7;
  late FakeLibraryApi api;

  Future<void> pump(WidgetTester tester) async {
    await setDesktopSize(tester);
    api = FakeLibraryApi([game(1, 'Okami'), game(2, 'Ico')])
      ..regular = const [
        RommCollection(id: 1, name: 'Favorites', isFavorite: true, userId: me, romIds: {1}, romCount: 1),
        RommCollection(id: 2, name: 'Couch co-op', userId: me, romIds: {1, 2}, romCount: 2, isPublic: true),
        RommCollection(id: 3, name: 'RPG classics', userId: 8, ownerUsername: 'anna', romCount: 64, isPublic: true),
      ]
      ..smart = const [RommCollection(id: 4, name: 'Never finished', kind: CollectionKind.smart, userId: me)]
      ..virtualByType = const {
        'franchise': [
          RommCollection(id: 0, name: 'Mario', kind: CollectionKind.virtual, virtualId: 'v1', virtualType: 'franchise'),
        ],
        'genre': [
          RommCollection(id: 0, name: 'Racing', kind: CollectionKind.virtual, virtualId: 'v2', virtualType: 'genre'),
        ],
      };
    await tester.pumpWidget(
      testApp(
        const CollectionsPage(),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          rommUserIdProvider.overrideWithValue(me),
          favouriteIdsProvider.overrideWithValue(const {}),
          gamesOnThisPcProvider.overrideWithValue([game(2, 'Ico')]),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String?> names(WidgetTester tester) =>
      tester.widgetList<Text>(find.byKey(const ValueKey('collection-name'))).map((t) => t.data).toList();

  testWidgets('the players\' collections in the panel (yours, smart, shared), then RomM\'s virtual ones by type', (
    tester,
  ) async {
    await pump(tester);
    expect(names(tester), ['Favourites', 'Couch co-op', 'Never finished', 'RPG classics', 'Mario', 'Racing']);
    expect(find.text('COLLECTIONS'), findsOneWidget);
    expect(find.text('VIRTUAL · FRANCHISE'), findsOneWidget);
    expect(find.text('VIRTUAL · GENRE'), findsOneWidget);
    expect(find.text('4 collections · 2 virtual'), findsOneWidget);
    // Marks: smart, shared, another player's, and how many are on this PC.
    expect(find.byKey(const ValueKey('mark-smart')), findsOneWidget);
    expect(find.byKey(const ValueKey('mark-shared')), findsNWidgets(2));
    expect(find.text('64 games · anna'), findsOneWidget);
    expect(find.text('1 on PC'), findsOneWidget);
    // Sort by sits at the right end of the bar.
    final sort = tester.getRect(find.byKey(const ValueKey('collections-sort')));
    final page = tester.getRect(find.byKey(const Key('page-Collections')));
    expect(page.right - sort.right, lessThan(GSpace.rowPad + 1));
  });

  testWidgets('Kind and Whose narrow it; Whose is off for Virtual', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('kind-Smart')));
    await tester.pumpAndSettle();
    expect(names(tester), ['Never finished']);
    await tester.tap(find.byKey(const ValueKey('kind-Virtual')));
    await tester.pumpAndSettle();
    expect(names(tester), ['Mario', 'Racing']);
    await tester.tap(find.byKey(const ValueKey("whose-Others'")));
    await tester.pumpAndSettle();
    expect(names(tester), ['Mario', 'Racing'], reason: 'Whose is off');
    await tester.tap(find.byKey(const ValueKey('kind-All')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("whose-Others'")));
    await tester.pumpAndSettle();
    expect(names(tester), ['RPG classics']);
  });

  testWidgets('A opens a smart collection as its gallery; Y opens a random game of a virtual one', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Never finished'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionScreen), findsOneWidget);
    expect(api.queries.last.$1.smartCollectionId, 4);
    await press(tester, GameAction.back);
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Mario'))).requestFocus();
    await tester.pump();
    await press(tester, GameAction.favorite);
    await tester.pumpAndSettle();
    expect(api.randomWithin, const GalleryQuery(virtualCollectionId: 'v1'));
    expect(find.byType(GameScreen), findsOneWidget);
  });
}
