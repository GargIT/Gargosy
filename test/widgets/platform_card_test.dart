import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/platform_covers.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/ui/pages/platform_card.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

final _ps2 = Platform.fromJson({
  'id': 3,
  'name': 'PlayStation 2',
  'slug': 'ps2',
  'fs_slug': 'ps2',
  'display_name': 'PlayStation 2',
  'rom_count': 412,
});

Future<void> _pump(WidgetTester tester, List<Game> covers, {VoidCallback? onOpen}) async {
  await tester.pumpWidget(
    testApp(
      Center(
        child: SizedBox(
          width: 290,
          height: PlatformCard.height,
          child: PlatformCard(platform: _ps2, onOpen: onOpen ?? () {}),
        ),
      ),
      overrides: [
        platformCoversChoiceProvider.overrideWith((ref) => PlatformCoversChoice(MemoryPrefs())),
        platformCoversProvider.overrideWith((ref, key) async => covers),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final games = [for (var i = 1; i <= 5; i++) Game.fromJson(gameJson(i, 'Game $i'))];

  testWidgets('name, "maker · year · count", the logo, five covers in the strip', (tester) async {
    await _pump(tester, games);
    expect(find.text('PlayStation 2'), findsOneWidget);
    expect(find.text('Sony · 2000 · 412 games'), findsOneWidget);
    expect(find.byKey(const ValueKey('strip-cover')), findsNWidgets(5));
    expect(find.byKey(const ValueKey('platform-strip-logo')), findsNothing);
  });

  testWidgets('fewer covers: that many', (tester) async {
    await _pump(tester, games.take(2).toList());
    expect(find.byKey(const ValueKey('strip-cover')), findsNWidgets(2));
  });

  testWidgets('no covers (none, or RomM failed): the logo large in the strip', (tester) async {
    await _pump(tester, const []);
    expect(find.byKey(const ValueKey('strip-cover')), findsNothing);
    expect(find.byKey(const ValueKey('platform-strip-logo')), findsOneWidget);
  });

  testWidgets('A or a click opens it', (tester) async {
    var opened = 0;
    await _pump(tester, games, onOpen: () => opened++);
    await tester.tap(find.byKey(const ValueKey('platform-card-3')));
    expect(opened, 1);
  });

  for (final n in [2, 4, 5]) {
    testWidgets('$n covers sit centred in the strip', (tester) async {
      await _pump(tester, games.take(n).toList());
      final covers = find.byKey(const ValueKey('strip-cover'));
      final xs = [for (var i = 0; i < n; i++) tester.getCenter(covers.at(i)).dx];
      final middle = xs.reduce((a, b) => a + b) / n;
      expect(middle, moreOrLessEquals(tester.getCenter(find.byKey(const ValueKey('platform-strip'))).dx, epsilon: 1));
    });
  }
}
