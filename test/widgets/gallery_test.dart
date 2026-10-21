import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/ui_provider.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/gallery_screen.dart';
import 'package:gargosy/ui/widgets/gallery_bar.dart';
import 'package:gargosy/ui/widgets/on_screen_keyboard.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  final games = [
    for (var i = 1; i <= 120; i++)
      Game.fromJson({
        ...gameJson(i, 'Game ${i.toString().padLeft(3, '0')}'),
        'metadatum': {
          'genres': [i.isEven ? 'Racing' : 'Action'],
        },
      }),
  ];

  Future<FakeLibraryApi> pump(WidgetTester tester, {Object? failWith, int? failFromOffset}) async {
    await setDesktopSize(tester);
    final api = FakeLibraryApi(games)
      ..failWith = failWith
      ..failFromOffset = failFromOffset;
    await tester.pumpWidget(
      testApp(
        const GalleryScreen(title: 'PlayStation 2', query: GalleryQuery(platformId: 1)),
        overrides: [libraryApiProvider.overrideWithValue(api), favouriteIdsProvider.overrideWithValue(const {})],
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('shows the title, the count and the first page; paging loads more', (tester) async {
    final api = await pump(tester);
    expect(find.text('PlayStation 2'), findsWidgets); // the title, and each card's platform line
    expect(find.text('120 games'), findsOneWidget);
    expect(find.text('Game 001'), findsWidgets);
    expect(api.queries.first.$1.platformId, 1);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(api.queries.map((q) => q.$2), containsAllInOrder([0, 48]));
  });

  testWidgets('Filters opens the sheet; choosing a genre reloads with it', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('bar-filters')));
    await tester.pumpAndSettle();
    expect(find.text('Filters'), findsWidgets);
    await tester.tap(find.text('Racing'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.genres, {'Racing'});
    expect(find.text('60 games'), findsOneWidget);
    expect(find.text('Filters · 1'), findsOneWidget);
  });

  testWidgets("Sort by lists RomM's and the player's fields under headings; a pick reloads in its order", (
    tester,
  ) async {
    final api = await pump(tester);
    await tester.tap(find.text('Sort by Name'));
    await tester.pumpAndSettle();
    expect(find.text('ROMM'), findsOneWidget);
    expect(find.text('YOURS'), findsOneWidget);
    expect(find.text('THIS PC'), findsNothing);
    expect(find.text('Downloaded'), findsNothing);
    await tester.tap(find.text('Length'));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.sort, GallerySort.length);
    expect(api.queries.last.$1.toParams(offset: 0, limit: 1)['order_by'], 'hltb_main_story');
    await tester.tap(find.text('Sort by Length'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My rating'));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.sort, GallerySort.myRating);
    expect(api.queries.last.$1.descending, isTrue);
  });

  testWidgets('the direction button flips the order', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('bar-direction')));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.descending, isTrue);
    expect(find.text('Descending'), findsOneWidget);
  });

  testWidgets('typing in the filter asks RomM once typing stops', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('filter-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-input')), 'Game 11');
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.queries.last.$1.search, isNull);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.search, 'Game 11');
    expect(api.queries.last.$1.platformId, 1);
    expect(find.text('10 games'), findsOneWidget); // Game 110 to 119
  });

  testWidgets('typing slowly: the box keeps focus through each reload, the cursor after the text', (tester) async {
    final api = await pump(tester);
    api.delay = const Duration(milliseconds: 300);
    await tester.tap(find.byKey(const ValueKey('filter-field')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('filter-input'));
    await tester.enterText(input, 'Game 1');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.search, 'Game 1');
    expect(input, findsOneWidget);
    final field = tester.widget<TextField>(input);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.selection, const TextSelection.collapsed(offset: 6));
    await tester.enterText(input, 'Game 11');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.search, 'Game 11');
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
  });

  testWidgets('editing again puts the cursor after the text', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('filter-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-input')), 'Game 12');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-field')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(const ValueKey('filter-input')));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.selection, const TextSelection.collapsed(offset: 7));
  });

  testWidgets('Escape while typing ends the typing and keeps the page; the text applies', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('filter-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-input')), 'Game 12');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filter-input')), findsNothing);
    expect(find.byType(GalleryScreen), findsOneWidget);
    expect(api.queries.last.$1.search, 'Game 12');
  });

  testWidgets('D-pad up from the first cover reaches the bar', (tester) async {
    await pump(tester);
    for (var i = 0; i < 4; i++) {
      await press(tester, GameAction.up);
    }
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(find.ancestor(of: find.byWidget(focused.widget), matching: find.byType(GalleryBar)), findsOneWidget);
  });

  testWidgets('with a controller, A on the filter opens the on-screen keyboard', (tester) async {
    await pump(tester);
    final field = find.byKey(const ValueKey('filter-field'));
    ProviderScope.containerOf(tester.element(field)).read(inputModeProvider.notifier).state = InputMode.gamepad;
    Focus.of(tester.element(find.descendant(of: field, matching: find.byType(Container)).first)).requestFocus();
    await tester.pump();
    await press(tester, GameAction.confirm);
    expect(find.byType(OnScreenKeyboard), findsOneWidget);
  });

  testWidgets("On this PC: only the platform's downloaded games, sorted by Gargosy, with RomM away", (tester) async {
    await setDesktopSize(tester);
    final api = FakeLibraryApi(games);
    final mine = [
      game(5, 'Zone of the Enders'),
      game(6, 'Ape Escape'),
      Game.fromJson({...gameJson(7, 'Halo'), 'platform_id': 9}),
    ];
    await tester.pumpWidget(
      testApp(
        const GalleryScreen(title: 'PlayStation 2', query: GalleryQuery(platformId: 1)),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          favouriteIdsProvider.overrideWithValue(const {}),
          gamesOnThisPcProvider.overrideWithValue(mine),
        ],
      ),
    );
    await tester.pumpAndSettle();
    api.failWith = Exception('SocketException: connection refused');
    final asked = api.queries.length;
    await tester.tap(find.byKey(const ValueKey('bar-this-pc')));
    await tester.pumpAndSettle();
    expect(find.text('On this PC · 2'), findsOneWidget);
    expect(find.text('Ape Escape'), findsWidgets);
    expect(find.text('Zone of the Enders'), findsWidgets);
    expect(find.text('Halo'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Ape Escape').last).dx,
      lessThan(tester.getTopLeft(find.text('Zone of the Enders').last).dx),
    );
    await tester.tap(find.text('Sort by Name'));
    await tester.pumpAndSettle();
    expect(find.text('THIS PC'), findsOneWidget);
    await tester.tap(find.text('Downloaded'));
    await tester.pumpAndSettle();
    expect(find.text('Sort by Downloaded'), findsOneWidget);
    expect(api.queries.length, asked);
    // Off again: Downloaded is Gargosy's, so RomM sorts by name.
    api.failWith = null;
    await tester.tap(find.byKey(const ValueKey('bar-this-pc')));
    await tester.pumpAndSettle();
    expect(find.text('Sort by Name'), findsOneWidget);
    expect(api.queries.last.$1.sort, GallerySort.name);
  });

  testWidgets('shows the error with retry', (tester) async {
    await pump(tester, failWith: Exception('SocketException: connection refused'));
    expect(find.textContaining("Can't reach RomM"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a later page that fails says so with Retry, and stops asking', (tester) async {
    final api = await pump(tester, failFromOffset: 48);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't load more"), findsOneWidget);
    final asked = api.queries.length;
    await tester.pump(const Duration(seconds: 10));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(api.queries.length, asked);
    api.failFromOffset = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(api.queries.length, asked + 1);
    expect(find.textContaining("Couldn't load more"), findsNothing);
  });
}
