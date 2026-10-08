import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/screens/gallery_screen.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  final games = [
    for (var i = 1; i <= 120; i++)
      Game.fromJson({...gameJson(i, 'Game ${i.toString().padLeft(3, '0')}'), 'metadatum': {'genres': [i.isEven ? 'Racing' : 'Action']}}),
  ];

  Future<FakeLibraryApi> pump(WidgetTester tester, {Object? failWith, int? failFromOffset}) async {
    await setDesktopSize(tester);
    final api = FakeLibraryApi(games)
      ..failWith = failWith
      ..failFromOffset = failFromOffset;
    await tester.pumpWidget(testApp(const GalleryScreen(title: 'PlayStation 2', query: GalleryQuery(platformId: 1)), overrides: [
      libraryApiProvider.overrideWithValue(api),
      favouriteIdsProvider.overrideWithValue(const {}),
    ]));
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

  testWidgets('X opens the filters; choosing a genre reloads with it', (tester) async {
    final api = await pump(tester);
    await press(tester, GameAction.detail);
    expect(find.text('Filters'), findsOneWidget);
    await tester.tap(find.text('Racing'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.genres, {'Racing'});
    expect(find.text('60 games'), findsOneWidget);
  });

  testWidgets('sorting from the filter sheet reloads in that order', (tester) async {
    final api = await pump(tester);
    await press(tester, GameAction.detail);
    await tester.tap(find.text('Recently added'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(api.queries.last.$1.sort, GallerySort.recentlyAdded);
    expect(api.queries.last.$1.descending, isTrue);
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
