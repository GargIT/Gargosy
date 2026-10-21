import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/gallery_screen.dart';
import 'package:gargosy/ui/screens/game/game_screen.dart';
import 'package:gargosy/ui/widgets/game_card.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

Map<String, dynamic> _version(int id, String tag, {List<(int, String)> others = const []}) => {
  ...gameJson(id, 'Ico', fsName: 'Ico ($tag).chd'),
  'regions': [tag],
  'sibling_roms': [
    for (final (oid, otag) in others) {'id': oid, 'name': 'Ico', 'fs_name_no_ext': 'Ico ($otag)'},
  ],
};

void main() {
  final usa = Game.fromJson(_version(1, 'USA', others: [(2, 'Europe'), (3, 'Japan')]));
  final eur = Game.fromJson(_version(2, 'Europe', others: [(1, 'USA'), (3, 'Japan')]));
  final jpn = Game.fromJson(_version(3, 'Japan', others: [(1, 'USA'), (2, 'Europe')]));
  final byId = {'1': usa, '2': eur, '3': jpn};

  late FakeLibraryApi api;

  Future<void> pump(WidgetTester tester, {List<Game> onPc = const []}) async {
    await setDesktopSize(tester);
    api = FakeLibraryApi([usa, game(9, 'Rez')]);
    await tester.pumpWidget(
      testApp(
        const GalleryScreen(title: 'PlayStation 2', query: GalleryQuery(platformId: 1)),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          favouriteIdsProvider.overrideWithValue(const {}),
          gamesOnThisPcProvider.overrideWithValue(onPc),
          gameProvider.overrideWith((ref, id) async => byId[id] ?? game(int.parse(id), 'Rez')),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  Game shownGame(WidgetTester tester) => tester.widget<GameScreen>(find.byType(GameScreen)).game;

  testWidgets('RomM is asked to fold versions; a folded card shows how many, and its region', (tester) async {
    await pump(tester);
    expect(api.folded, everyElement(isTrue));
    expect(find.byKey(const ValueKey('card-versions')), findsOneWidget); // Ico, not Rez
    expect(find.descendant(of: find.byKey(const ValueKey('card-versions')), matching: find.text('3')), findsOneWidget);
    expect(find.text('USA'), findsOneWidget);
  });

  testWidgets('no version on this PC: RomM\'s own opens', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Ico').first);
    await tester.pumpAndSettle();
    expect(shownGame(tester).id, '1');
  });

  testWidgets('one version on this PC: that one opens, without asking', (tester) async {
    await pump(tester, onPc: [jpn]);
    await tester.tap(find.text('Ico').first);
    await tester.pumpAndSettle();
    expect(find.text('Which version?'), findsNothing);
    expect(shownGame(tester).id, '3');
  });

  testWidgets('two on this PC: it asks which version', (tester) async {
    await pump(tester, onPc: [usa, eur]);
    await tester.tap(find.text('Ico').first);
    await tester.pumpAndSettle();
    expect(find.text('Which version?'), findsOneWidget);
    expect(find.text('(Japan)'), findsNothing, reason: 'only the ones on this PC');
    await tester.tap(find.text('(Europe)'));
    await tester.pumpAndSettle();
    expect(shownGame(tester).id, '2');
  });

  testWidgets("versions RomM didn't group (matched by different ids) still fold into one card", (tester) async {
    await setDesktopSize(tester);
    // As RomM sends a patched copy without IGDB's id: both listed, each the other's sibling.
    final original = Game.fromJson({
      ...gameJson(10, '007 Agent Under Fire', fsName: '007 Agent Under Fire (USA).chd'),
      'sibling_roms': [
        {'id': 11, 'name': '007 Agent Under Fire', 'fs_name_no_ext': '007 Agent Under Fire (USA) (Widescreen)'},
      ],
    });
    final hack = Game.fromJson({
      ...gameJson(11, '007 Agent Under Fire', fsName: '007 Agent Under Fire (USA) (Widescreen).chd'),
      'sibling_roms': [
        {'id': 10, 'name': '007 Agent Under Fire', 'fs_name_no_ext': '007 Agent Under Fire (USA)'},
      ],
    });
    await tester.pumpWidget(
      testApp(
        const GalleryScreen(title: 'PlayStation 2', query: GalleryQuery(platformId: 1)),
        overrides: [
          libraryApiProvider.overrideWithValue(FakeLibraryApi([original, hack, game(12, 'Burnout 3')])),
          favouriteIdsProvider.overrideWithValue(const {}),
          gamesOnThisPcProvider.overrideWithValue(const []),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('card-versions')), findsOneWidget);
    expect(find.byType(GameCard), findsNWidgets(2));
    // The A–Z rail's offsets are RomM's: B is at 2 there, the second card here.
    await tester.tap(find.byKey(const ValueKey('rail-B')));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<GameCard>()?.game.name,
      'Burnout 3',
    );
  });

  testWidgets("the game page's Version switches to another version's page", (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(
      testApp(
        GameScreen(game: usa),
        overrides: [
          libraryApiProvider.overrideWithValue(FakeLibraryApi(const [])),
          favouriteIdsProvider.overrideWithValue(const {}),
          gamesOnThisPcProvider.overrideWithValue([jpn]),
          gameProvider.overrideWith((ref, id) async => byId[id]),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Version: (USA)  (3)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('game-version')));
    await tester.pumpAndSettle();
    expect(find.text('(Japan)  ·  on this PC'), findsOneWidget);
    await tester.tap(find.text('(Japan)  ·  on this PC'));
    await tester.pumpAndSettle();
    expect(shownGame(tester).id, '3');
    expect(find.text('Version: (Japan)  (3)'), findsOneWidget);
  });
}
