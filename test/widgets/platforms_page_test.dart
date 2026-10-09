import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/platform_covers.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/pages/platform_card.dart';
import 'package:gargosy/ui/pages/platforms_page.dart';
import 'package:gargosy/ui/screens/gallery_screen.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

Platform plat(int id, String name, String slug, int count) =>
    Platform.fromJson({'id': id, 'name': name, 'slug': slug, 'fs_slug': slug, 'display_name': name, 'rom_count': count});

void main() {
  late MemoryPrefs prefs;

  Future<void> pumpPage(WidgetTester tester, {double width = 1920, List<Platform>? list}) async {
    tester.view.physicalSize = Size(width, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    prefs = MemoryPrefs();
    await tester.pumpWidget(testApp(const PlatformsPage(), overrides: [
      platformsProvider.overrideWith((ref) async =>
          list ?? [plat(1, 'PlayStation 2', 'ps2', 1335), plat(2, 'Dreamcast', 'dc', 91)]),
      libraryApiProvider.overrideWithValue(FakeLibraryApi(const [])),
      favouriteIdsProvider.overrideWithValue(const {}),
      platformCoversChoiceProvider.overrideWith((ref) => PlatformCoversChoice(prefs)),
    ]));
    await tester.pumpAndSettle();
  }

  testWidgets('heading with the counts; a card per platform; A opens its gallery', (tester) async {
    await pumpPage(tester);
    expect(find.text('Platforms'), findsOneWidget);
    expect(find.byKey(const ValueKey('platforms-heading')), findsOneWidget);
    expect(find.text('2 platforms · 1426 games'), findsOneWidget);
    expect(find.text('Sony · 2000 · 1335 games'), findsOneWidget);
    expect(find.byType(PlatformCard), findsNWidgets(2));
    await press(tester, GameAction.confirm);
    expect(find.byType(GalleryScreen), findsOneWidget);
  });

  for (final (width, perRow) in [(1920.0, 6), (1280.0, 4), (900.0, 3)]) {
    testWidgets('${width.toInt()} px wide: $perRow cards in the first row', (tester) async {
      await pumpPage(tester, width: width, list: [for (var i = 1; i <= 12; i++) plat(i, 'P$i', 'p$i', 10)]);
      final cards = find.byType(PlatformCard);
      final top = tester.getTopLeft(cards.first).dy;
      final firstRow = [for (var i = 0; i < cards.evaluate().length; i++) tester.getTopLeft(cards.at(i)).dy]
          .where((dy) => dy == top);
      expect(firstRow, hasLength(perRow));
    });
  }

  testWidgets('a long name at 900 px: one line, no overflow', (tester) async {
    await pumpPage(tester,
        width: 900, list: [plat(1, 'Nintendo Entertainment System (Famicom Disk System edition)', 'nes', 3)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Covers: four choices; the pick is kept for the profile', (tester) async {
    await pumpPage(tester);
    expect(find.text('Covers: Top rated'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('platforms-covers')));
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('dropdown-list'));
    for (final c in PlatformCovers.values) {
      expect(find.descendant(of: list, matching: find.text(c.label)), findsOneWidget);
    }
    await tester.tap(find.descendant(of: list, matching: find.text('Random')));
    await tester.pumpAndSettle();
    expect(find.text('Covers: Random'), findsOneWidget);
    expect(PlatformCoversChoice(prefs).state, PlatformCovers.random);
  });

  testWidgets('D-pad up from the first row reaches the Covers setting', (tester) async {
    await pumpPage(tester);
    await press(tester, GameAction.up);
    await press(tester, GameAction.confirm);
    expect(find.byKey(const ValueKey('dropdown-list')), findsOneWidget);
  });

  testWidgets('shows the error with retry', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const PlatformsPage(), overrides: [
      platformsProvider.overrideWith((ref) async => throw Exception('SocketException: connection refused')),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });
}
