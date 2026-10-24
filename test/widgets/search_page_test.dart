import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/library/library_snapshot.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/ui_provider.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/pages/search_page.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  late FakeLibraryApi api;

  Future<void> pump(WidgetTester tester, List<String> names) async {
    await setDesktopSize(tester);
    api = FakeLibraryApi([for (var i = 0; i < names.length; i++) game(i + 1, names[i])]);
    await tester.pumpWidget(
      testApp(
        const SearchPage(),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          favouriteIdsProvider.overrideWithValue(const {}),
          gamesOnThisPcProvider.overrideWithValue([game(1, 'Okami')]),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  String stat(WidgetTester tester, String key) =>
      tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))).first.data!;

  testWidgets('before typing: the whole library by name, counted in the header', (tester) async {
    await pump(tester, ['Okami', 'Ico', 'Okamiden']);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Search your library'), findsOneWidget);
    final first = api.queries.firstWhere((q) => q.$1.sort == GallerySort.name).$1;
    expect(first.search, isNull);
    for (final name in ['Okami', 'Ico', 'Okamiden']) {
      expect(find.text(name), findsWidgets);
    }
    expect(stat(tester, 'search-games'), '3');
    expect(stat(tester, 'search-on-pc'), '1');
    expect(find.text('Sort by Name'), findsOneWidget);
  });

  testWidgets('a term from the controller keyboard sorts by Best match; cleared, the library by name again', (
    tester,
  ) async {
    await pump(tester, ['Okami', 'Ico', 'Okamiden']);
    final field = find.byKey(const ValueKey('filter-field'));
    ProviderScope.containerOf(tester.element(field)).read(inputModeProvider.notifier).state = InputMode.gamepad;
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.ancestor(of: find.byWidget(focused.widget), matching: field),
      findsOneWidget,
      reason: 'the box has focus',
    );
    await press(tester, GameAction.confirm); // the on-screen keyboard opens
    for (final ch in 'okami'.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey.findKeyByKeyId(ch.codeUnitAt(0))!, character: ch);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final asked = api.queries.last.$1;
    expect((asked.search, asked.sort), ('okami', GallerySort.bestMatch));
    expect(find.text('Okamiden'), findsWidgets);
    expect(find.text('Ico'), findsNothing);
    expect(find.text('Sort by Best match'), findsOneWidget);
    expect(stat(tester, 'search-games'), '2');

    await tester.tap(find.byKey(const ValueKey('filter-clear')));
    await tester.pumpAndSettle();
    expect((api.queries.last.$1.search, api.queries.last.$1.sort), (null, GallerySort.name));
    expect(find.text('Ico'), findsWidgets);
  });

  testWidgets('a sort picked while searching is kept as the term changes', (tester) async {
    await pump(tester, ['Okami', 'Ico', 'Okamiden']);
    await tester.tap(find.byKey(const ValueKey('filter-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-input')), 'oka');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.sort, GallerySort.bestMatch);
    await tester.tap(find.byKey(const ValueKey('bar-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rating'));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.sort, GallerySort.rating);

    await tester.tap(find.byKey(const ValueKey('filter-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-input')), 'okami');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect((api.queries.last.$1.search, api.queries.last.$1.sort), ('okami', GallerySort.rating));
  });

  testWidgets('scrolled, the header goes and the box moves onto the bar', (tester) async {
    await pump(tester, [for (var i = 0; i < 80; i++) 'Game ${i.toString().padLeft(3, '0')}']);
    expect(find.byKey(const ValueKey('search-header')), findsOneWidget);
    await tester.drag(find.text('Game 000').first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-header')), findsNothing);
    expect(find.byKey(const ValueKey('filter-field')), findsOneWidget, reason: 'the one box, on the bar now');
  });

  testWidgets('a submitted term goes into Recent; A runs one, hold A forgets it', (tester) async {
    await pump(tester, ['Okami', 'Ico', 'Okamiden']);
    expect(find.byKey(const ValueKey('search-recent')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('filter-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-input')), 'oka');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-recent')), findsNothing, reason: 'typed, not yet meant');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-input')), 'ico');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-ico')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-oka')), findsOneWidget);
    expect(api.queries.last.$1.search, 'ico');

    await tester.tap(find.byKey(const ValueKey('recent-oka')));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.search, 'oka');
    expect(find.text('Okamiden'), findsWidgets);
    expect(find.text('Ico'), findsNothing);
    final chips = tester.widgetList<Widget>(
      find.descendant(
        of: find.byKey(const ValueKey('search-recent')),
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('recent-') &&
              !(w.key! as ValueKey<String>).value.startsWith('recent-forget'),
        ),
      ),
    );
    expect(
      [for (final c in chips) (c.key! as ValueKey<String>).value],
      ['recent-oka', 'recent-ico'],
      reason: 'run, it comes first',
    );

    await tester.longPress(find.byKey(const ValueKey('recent-ico')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-ico')), findsNothing);
    expect(find.byKey(const ValueKey('recent-oka')), findsOneWidget);
  });

  testWidgets('nothing matches with On this PC: says so and Show all turns it off', (tester) async {
    await pump(tester, ['Okami', 'Ico', 'Okamiden']);
    await tester.tap(find.byKey(const ValueKey('filter-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-input')), 'ico');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bar-this-pc')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nothing-matches')), findsOneWidget);
    expect(find.text('Nothing matches “ico” here.'), findsOneWidget);
    expect(find.text('RomM has 1 game that matches, hidden by On this PC.'), findsOneWidget);
    await tester.tap(find.text('Show all 1'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nothing-matches')), findsNothing);
    expect(find.text('Ico'), findsWidgets);
    expect(api.queries.last.$1.search, 'ico');
  });

  testWidgets('nothing matches anywhere: only the plain line, no Show all', (tester) async {
    await pump(tester, ['Okami', 'Ico']);
    await tester.tap(find.byKey(const ValueKey('filter-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('filter-input')), 'zelda');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches "zelda".'), findsOneWidget);
    expect(find.byKey(const ValueKey('show-all')), findsNothing);
  });

  testWidgets('B on the box clears the term; on an empty box it goes back', (tester) async {
    await pump(tester, ['Okami', 'Ico', 'Okamiden']);
    final nav = Navigator.of(tester.element(find.byType(SearchPage)));
    nav.push(MaterialPageRoute<void>(builder: (_) => const Material(child: SearchPage())));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget, reason: 'the first one is under the route');
    ProviderScope.containerOf(tester.element(find.byType(SearchPage))).read(inputModeProvider.notifier).state =
        InputMode.gamepad;
    await tester.pump();
    await press(tester, GameAction.confirm);
    for (final ch in 'ico'.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey.findKeyByKeyId(ch.codeUnitAt(0))!, character: ch);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.search, 'ico');

    await press(tester, GameAction.back);
    expect(api.queries.last.$1.search, isNull);
    expect(find.text('Search your library'), findsOneWidget, reason: 'the box is empty, still on this page');
    expect(nav.canPop(), isTrue);

    await press(tester, GameAction.back);
    expect(nav.canPop(), isFalse, reason: 'B on the empty box went back');
  });
}
