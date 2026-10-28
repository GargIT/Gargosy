import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/collection/collection_screen.dart';
import 'package:gargosy/ui/screens/game/game_screen.dart';

import '../helpers/fake_collection_edits.dart';
import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  late FakeLibraryApi api;

  Future<void> pump(
    WidgetTester tester,
    RommCollection c, {
    int games = 3,
    List<int> platformIds = const [],
    List<Platform> platforms = const [],
    FakeCollectionEdits? edits,
  }) async {
    await setDesktopSize(tester);
    api = FakeLibraryApi([
      for (var i = 1; i <= games; i++) game(i, 'Game ${i.toString().padLeft(3, '0')}'),
    ], values: FilterValues(platforms: platformIds));
    await tester.pumpWidget(
      testApp(
        CollectionScreen(collection: c),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          rommUserIdProvider.overrideWithValue(7),
          favouriteIdsProvider.overrideWithValue(const {}),
          gamesOnThisPcProvider.overrideWithValue([game(2, 'Game 002')]),
          platformsProvider.overrideWith((ref) => platforms),
          collectionEditsProvider.overrideWithValue(edits),
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

  testWidgets("⋯ on your own collection (#144): share it, rename it; not on another player's", (tester) async {
    const mine = RommCollection(id: 2, name: 'Couch co-op', userId: 7, romIds: {1, 2, 3}, romCount: 3);
    final edits = FakeCollectionEdits([mine]);
    await pump(tester, mine, edits: edits);
    await tester.tap(find.byKey(const ValueKey('collection-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share with every player'));
    await tester.pumpAndSettle();
    expect(edits.calls, ['share 2 true']);
    expect(find.text('Shared on RomM'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('collection-more')));
    await tester.pumpAndSettle();
    expect(find.text('Stop sharing'), findsOneWidget);
    await tester.tap(find.text('Delete collection…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Its games stay in the library'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(edits.calls, ['share 2 true']);

    await pump(tester, const RommCollection(id: 5, name: "Bob's", userId: 8, isPublic: true), edits: edits);
    expect(find.byKey(const ValueKey('collection-more')), findsNothing);
  });

  testWidgets("⋯ on your own smart collection (#188): rename keeps it smart", (tester) async {
    const mine = RommCollection(id: 4, name: 'Racing', kind: CollectionKind.smart, userId: 7);
    final edits = FakeCollectionEdits([mine]);
    await pump(tester, mine, edits: edits);
    await tester.tap(find.byKey(const ValueKey('collection-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share with every player'));
    await tester.pumpAndSettle();
    expect(edits.calls, ['share 4 true']);
    expect(find.text('Smart collection'), findsOneWidget);
    expect(find.text('Shared on RomM'), findsOneWidget);
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

    // RomM's filter_summary is its criteria as JSON: said in words instead.
    await pump(
      tester,
      RommCollection.fromJson(const {
        'id': 5,
        'name': 'Girls',
        'filter_summary': '{"order_by": "name", "order_dir": "asc", "search_term": "girl"}',
      }, kind: CollectionKind.smart),
    );
    expect(find.text('Search “girl” · Sorted by Name, A–Z'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing);
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

  testWidgets("its platforms: counted in the header, picked on the bar, RomM asked for the collection's games there", (
    tester,
  ) async {
    Platform platform(int id, String name) => Platform(id: id, name: name, slug: name.toLowerCase(), gamesCount: 9);
    await pump(
      tester,
      const RommCollection(id: 2, name: 'Couch co-op', romIds: {1, 2, 3}, romCount: 3),
      platformIds: [4, 5],
      platforms: [platform(3, 'Dreamcast'), platform(4, 'N64'), platform(5, 'SNES')],
    );
    expect(find.text('PLATFORMS'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('collection-platforms')), matching: find.text('2')),
      findsOneWidget,
      reason: 'the ids RomM gave, not every platform',
    );
    expect(find.text('Platform: All 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bar-platform')));
    await tester.pumpAndSettle();
    expect(find.text('Dreamcast'), findsNothing);
    await tester.tap(find.text('SNES'));
    await tester.pumpAndSettle();
    expect(find.text('Platform: SNES'), findsOneWidget);
    final asked = api.queries.last.$1;
    expect((asked.collectionId, asked.platformId), (2, 5));
    expect(find.byKey(const ValueKey('bar-scan')), findsNothing);
    expect(find.text('Platform: SNES'), findsOneWidget, reason: 'the list stays the whole collection\'s');

    await tester.tap(find.byKey(const ValueKey('bar-platform')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All 2'));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.platformId, isNull);
  });

  testWidgets('one platform: no pick, the count still shows', (tester) async {
    await pump(
      tester,
      const RommCollection(id: 2, name: 'N64 only', romIds: {1}, romCount: 1),
      platformIds: [4],
      platforms: [Platform(id: 4, name: 'N64', slug: 'n64', gamesCount: 9)],
    );
    expect(find.text('PLATFORMS'), findsOneWidget);
    expect(find.byKey(const ValueKey('bar-platform')), findsNothing);
  });
}
