import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/collection/collection_screen.dart';
import 'package:gargosy/ui/screens/game/game_screen.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  late FakeLibraryApi api;

  Future<void> pump(WidgetTester tester, RommCollection c, {int games = 3}) async {
    await setDesktopSize(tester);
    api = FakeLibraryApi([for (var i = 1; i <= games; i++) game(i, 'Game ${i.toString().padLeft(3, '0')}')]);
    await tester.pumpWidget(
      testApp(
        CollectionScreen(collection: c),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          rommUserIdProvider.overrideWithValue(7),
          favouriteIdsProvider.overrideWithValue(const {}),
          gamesOnThisPcProvider.overrideWithValue([game(2, 'Game 002')]),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("the header: name, kind, shared, whose, description, games and on this PC; the games are its own", (
    tester,
  ) async {
    await pump(
      tester,
      const RommCollection(
        id: 2,
        name: 'Couch co-op',
        description: 'Two players or more.',
        userId: 7,
        isPublic: true,
        romIds: {1, 2, 3},
        romCount: 3,
      ),
    );
    expect(find.byKey(const ValueKey('collection-header')), findsOneWidget);
    expect(find.text('Couch co-op'), findsOneWidget);
    expect(find.text('Collection'), findsOneWidget);
    expect(find.text('Shared on RomM'), findsOneWidget);
    expect(find.text('By you'), findsOneWidget);
    expect(find.text('Two players or more.'), findsOneWidget);
    expect(find.text('GAMES'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'one of its games on this PC');
    expect(api.queries.first.$1.collectionId, 2);
  });

  testWidgets("a smart one says its filters and whose; a virtual one its type; Random picks within it", (tester) async {
    await pump(
      tester,
      const RommCollection(
        id: 4,
        name: 'Never finished',
        kind: CollectionKind.smart,
        filterSummary: 'Status: unfinished',
        userId: 8,
        ownerUsername: 'anna',
      ),
    );
    expect(find.text('Smart collection'), findsOneWidget);
    expect(find.text('Status: unfinished'), findsOneWidget);
    expect(find.text('By anna'), findsOneWidget);
    expect(api.queries.first.$1.smartCollectionId, 4);

    await pump(
      tester,
      const RommCollection(
        id: 0,
        name: 'Mario',
        kind: CollectionKind.virtual,
        virtualId: 'v1',
        virtualType: 'franchise',
      ),
    );
    expect(find.text('Virtual · Franchise'), findsOneWidget);
    expect(find.textContaining('By '), findsNothing);
    await tester.tap(find.byKey(const ValueKey('collection-random')));
    await tester.pumpAndSettle();
    expect(api.randomWithin, const GalleryQuery(virtualCollectionId: 'v1'));
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('scrolled, the header goes and the name stays above the bar', (tester) async {
    await pump(tester, const RommCollection(id: 2, name: 'Big one', romCount: 200), games: 200);
    await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('collection-header')), findsNothing);
    expect(find.byKey(const ValueKey('collection-pinned-name')), findsOneWidget);
  });
}
