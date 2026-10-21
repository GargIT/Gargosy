import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/letter_index.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/gallery_screen.dart';
import 'package:gargosy/ui/widgets/g_focusable.dart';
import 'package:gargosy/ui/widgets/game_card.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  // In name order, as RomM sends them: 4 under #, then 10 under each letter
  // there is (no Q, X or Z), so T's first game is far beyond the first page.
  final letters = [for (final l in 'ABCDEFGHIJKLMNOPRSTUVWY'.split('')) l];
  final games = [
    for (var i = 0; i < 4; i++) game(i + 1, '${1940 + i} Arcade'),
    for (final l in letters)
      for (var i = 0; i < 10; i++) game(100 + letters.indexOf(l) * 10 + i, '$l game ${i.toString().padLeft(2, '0')}'),
  ];

  late FakeLibraryApi api;

  Future<void> pump(WidgetTester tester, {List<Game> onPc = const []}) async {
    await setDesktopSize(tester);
    api = FakeLibraryApi(games);
    await tester.pumpWidget(
      testApp(
        const GalleryScreen(title: 'PlayStation 2', query: GalleryQuery(platformId: 1)),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          favouriteIdsProvider.overrideWithValue(const {}),
          gamesOnThisPcProvider.overrideWithValue(onPc),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  String? focusedGame() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<GameCard>()?.game.name;
  String? focusedLetter() {
    final key = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<GFocusable>()?.key;
    return key is ValueKey<String> && key.value.startsWith('rail-') ? key.value : null;
  }

  /// Up or down the rail to [letter].
  Future<void> moveOnRail(WidgetTester tester, String letter) async {
    for (var i = 0; i < 30 && focusedLetter() != 'rail-$letter'; i++) {
      final at = railLetters.indexOf(focusedLetter()!.substring(5));
      await press(tester, at > railLetters.indexOf(letter) ? GameAction.up : GameAction.down);
    }
  }

  testWidgets('sorted by name: # and the letters with games are on the rail; the rest are greyed', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('alphabet-rail')), findsOneWidget);
    for (final l in ['#', 'A', 'T', 'Y']) {
      expect(find.byKey(ValueKey('rail-$l')), findsOneWidget, reason: l);
    }
    for (final l in ['Q', 'X', 'Z']) {
      expect(find.byKey(ValueKey('rail-$l')), findsNothing, reason: l);
      expect(find.text(l), findsOneWidget, reason: '$l is shown, greyed');
    }
    expect(api.queries.first.$1.sort, GallerySort.name);
  });

  testWidgets("a click on T loads up to T's first game in one request, scrolls to it and focuses it", (tester) async {
    await pump(tester);
    final before = api.queries.length;
    await tester.tap(find.byKey(const ValueKey('rail-T')));
    await tester.pumpAndSettle();
    // T's first game is at 184 (4 under #, then 18 letters of 10): all of it in one request.
    expect(api.queries[before].$2 + api.limits[before], greaterThan(184));
    expect(focusedGame(), 'T game 00');
    final card = tester.getRect(find.ancestor(of: find.text('T game 00').last, matching: find.byType(GameCard)));
    expect(card.top, greaterThanOrEqualTo(0));
    expect(card.bottom, lessThanOrEqualTo(1080));
  });

  testWidgets('with the D-pad: right from the last column reaches the rail, down picks, left jumps', (tester) async {
    await pump(tester);
    for (var i = 0; i < 20 && focusedLetter() == null; i++) {
      await press(tester, GameAction.right);
    }
    expect(focusedLetter(), isNotNull);
    expect(focusedLetter(), startsWith('rail-'));
    // Down to D, past the letters without games.
    await moveOnRail(tester, 'D');
    expect(focusedLetter(), 'rail-D');
    await press(tester, GameAction.left);
    expect(focusedGame(), 'D game 00');
    // And A on a letter does the same.
    for (var i = 0; i < 20 && focusedLetter() == null; i++) {
      await press(tester, GameAction.right);
    }
    await moveOnRail(tester, 'B');
    await press(tester, GameAction.confirm);
    expect(focusedGame(), 'B game 00');
  });

  testWidgets("X puts focus on the rail at the focused game's letter", (tester) async {
    await pump(tester);
    // From the bar, no cover focused: the first game shown, under #.
    final direction = find.byKey(const ValueKey('bar-direction'));
    Focus.of(tester.element(find.descendant(of: direction, matching: find.byType(Container)).first)).requestFocus();
    await tester.pump();
    await press(tester, GameAction.detail);
    expect(focusedLetter(), 'rail-#');
    await tester.tap(find.byKey(const ValueKey('rail-T')));
    await tester.pumpAndSettle();
    expect(focusedGame(), 'T game 00');
    await press(tester, GameAction.detail);
    expect(focusedLetter(), 'rail-T');
    await press(tester, GameAction.down);
    await press(tester, GameAction.left);
    expect(focusedGame(), 'U game 00');
  });

  testWidgets('X does nothing without the rail', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Sort by Name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    final before = FocusManager.instance.primaryFocus;
    await press(tester, GameAction.detail);
    expect(FocusManager.instance.primaryFocus, before);
  });

  testWidgets('only by name: another sort has no rail', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Sort by Name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('alphabet-rail')), findsNothing);
  });

  testWidgets("On this PC: the rail is the downloaded games' own", (tester) async {
    await pump(tester, onPc: [game(5, 'Ico'), game(6, 'Rez'), game(7, '.hack Infection')]);
    await tester.tap(find.byKey(const ValueKey('bar-this-pc')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rail-I')), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-#')), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-A')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('rail-R')));
    await tester.pumpAndSettle();
    expect(focusedGame(), 'Rez');
  });
}
