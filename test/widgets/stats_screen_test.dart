import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/library/profile_stats.dart';
import 'package:gargosy/providers/stats_providers.dart';
import 'package:gargosy/ui/screens/stats_screen.dart';
import 'package:gargosy/ui/widgets/g_focusable.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  final now = DateTime(2026, 10, 31, 20);
  final sessions = <StatSession>[
    (gameId: '1', start: DateTime(2026, 10, 31, 18), end: DateTime(2026, 10, 31, 19)),
    (gameId: '2', start: DateTime(2026, 10, 30, 18), end: DateTime(2026, 10, 30, 20)),
    (gameId: '9', start: DateTime(2026, 10, 29, 18), end: DateTime(2026, 10, 29, 18, 10)),
  ];

  /// The key of the focused row.
  Key? focused() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<GFocusable>()?.key;

  Future<void> pump(WidgetTester tester, StatsView view) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(
      testApp(const StatsScreen(), overrides: [profileStatsProvider.overrideWith((ref) async => view)]),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the numbers, the most played first with the D-pad, time by platform', (tester) async {
    await pump(
      tester,
      StatsView(
        stats: ProfileStats.of(sessions, now),
        games: {'1': game(1, 'Okami'), '2': game(2, 'Ico')},
        thisPcOnly: false,
        finished: 4,
        achievementsThisMonth: 12,
      ),
    );
    String tile(String key) => tester
        .widgetList<Text>(find.descendant(of: find.byKey(ValueKey('stat-$key')), matching: find.byType(Text)))
        .last
        .data!;
    expect(tile('finished'), '4');
    expect(tile('achievements'), '12');
    expect(tile('streak'), '3');
    expect(find.byKey(const ValueKey('stats-this-pc')), findsNothing);
    expect(tester.getTopLeft(find.text('Ico').last).dy, lessThan(tester.getTopLeft(find.text('Okami').last).dy));
    expect(find.text('Game 9'), findsWidgets, reason: "a game RomM couldn't name");
    expect(find.text('BY PLATFORM'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(focused(), const ValueKey('stats-game-2'));
    await press(tester, GameAction.down);
    expect(focused(), const ValueKey('stats-game-1'));
  });

  testWidgets("offline: this PC's play, said; what RomM knows shows a dash", (tester) async {
    await pump(tester, StatsView(stats: ProfileStats.of(sessions, now), games: const {}, thisPcOnly: true));
    expect(find.byKey(const ValueKey('stats-this-pc')), findsOneWidget);
    expect(find.text('–'), findsNWidgets(2));
  });
}
