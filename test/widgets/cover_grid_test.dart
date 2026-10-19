import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/ui/widgets/cover_grid.dart';
import 'package:gargosy/ui/widgets/game_card.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  final games = [for (var i = 1; i <= 30; i++) game(i, 'Game $i')];

  String focusedName() {
    final ctx = FocusManager.instance.primaryFocus!.context!;
    return ctx.findAncestorWidgetOfExactType<GameCard>()!.game.name;
  }

  testWidgets('the D-pad wraps from the end of a row to the start of the next and back', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(
      testApp(
        SizedBox(
          width: 700, // room for 3 columns of 158 + gaps
          child: CoverGrid(games: games, coverUrl: (_) => null, onOpen: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(focusedName(), 'Game 1');
    final perRow = CoverGrid.columnsFor(700);
    for (var i = 1; i < perRow; i++) {
      await press(tester, GameAction.right);
    }
    expect(focusedName(), 'Game $perRow');
    await press(tester, GameAction.right);
    expect(focusedName(), 'Game ${perRow + 1}');
    await press(tester, GameAction.left);
    expect(focusedName(), 'Game $perRow');
    await press(tester, GameAction.down);
    expect(focusedName(), 'Game ${perRow * 2}');
  });

  testWidgets('asks for more when focus nears the end', (tester) async {
    await setDesktopSize(tester);
    var asked = 0;
    await tester.pumpWidget(
      testApp(CoverGrid(games: games, total: 100, coverUrl: (_) => null, onOpen: (_) {}, onEndReached: () => asked++)),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CoverGrid), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(asked, greaterThan(0));
  });

  testWidgets('an empty grid says so', (tester) async {
    await tester.pumpWidget(
      testApp(CoverGrid(games: const [], coverUrl: (_) => null, onOpen: (_) {}, emptyText: 'No games here')),
    );
    expect(find.text('No games here'), findsOneWidget);
  });
}
