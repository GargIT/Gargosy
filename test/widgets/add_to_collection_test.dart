import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/game/add_to_collection.dart';

import '../helpers/fake_collection_edits.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  final okami = game(9, 'Okami');

  testWidgets("your own collections, Favourites first, ✓ where it is; A puts it in or takes it out", (tester) async {
    await setDesktopSize(tester);
    final edits = FakeCollectionEdits([
      const RommCollection(id: 3, name: 'RPGs', userId: 7, romIds: {9}, romCount: 1),
      const RommCollection(id: 4, name: 'Couch', userId: 7),
      const RommCollection(id: 5, name: "Bob's", userId: 8, isPublic: true),
      const RommCollection(id: 6, name: 'Favorites', userId: 7, isFavorite: true),
    ]);
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) =>
              TextButton(onPressed: () => showAddToCollection(context, okami), child: const Text('open')),
        ),
        overrides: [
          collectionEditsProvider.overrideWithValue(edits),
          collectionsProvider.overrideWith((ref) async => [...edits.all]),
          rommUserIdProvider.overrideWithValue(7),
        ],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Favourites') < y('Couch') && y('Couch') < y('RPGs'), isTrue);
    expect(find.text("Bob's"), findsNothing, reason: "another player's");
    Finder checkOf(int i) =>
        find.descendant(of: find.byKey(ValueKey('collection-pick-$i')), matching: find.byIcon(Icons.check_box));
    expect(checkOf(2), findsOneWidget, reason: 'RPGs has it');
    expect(checkOf(1), findsNothing);

    await press(tester, GameAction.down); // Couch
    await press(tester, GameAction.confirm);
    await tester.pumpAndSettle();
    expect(edits.calls, ['in 4 9']);
    expect(checkOf(1), findsOneWidget);
    await press(tester, GameAction.down); // RPGs
    await press(tester, GameAction.confirm);
    await tester.pumpAndSettle();
    expect(edits.calls, ['in 4 9', 'out 3 9']);
    expect(checkOf(2), findsNothing);
    expect(find.text('New collection…'), findsOneWidget);
  });
}
