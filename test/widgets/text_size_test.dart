import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/ui/theme/text_size.dart';
import 'package:gargosy/ui/widgets/game_card.dart';
import 'package:gargosy/ui/widgets/shelf.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  testWidgets('ScaledText: every text at the size chosen; 100 % changes nothing', (tester) async {
    late TextScaler seen;
    Widget probe() => Builder(
      builder: (context) {
        seen = MediaQuery.textScalerOf(context);
        return const SizedBox();
      },
    );
    await tester.pumpWidget(MaterialApp(home: ScaledText(percent: 150, child: probe())));
    expect(seen.scale(10), 15);
    await tester.pumpWidget(MaterialApp(home: ScaledText(percent: 100, child: probe())));
    expect(seen.scale(10), 10);
  });

  testWidgets('ScaledText goes on top of the Windows text size, never under it', (tester) async {
    late TextScaler seen;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
          child: ScaledText(
            percent: 150,
            child: Builder(
              builder: (context) {
                seen = MediaQuery.textScalerOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    expect(seen.scale(10), closeTo(18.75, 0.001));
  });

  for (final scale in [1.0, 1.25, 1.5]) {
    testWidgets('at ${(scale * 100).round()} % a shelf of game cards fits its text at 1280 × 720', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final games = <Game>[for (var i = 1; i <= 8; i++) game(i, 'A rather long game name number $i')];
      await tester.pumpWidget(
        testApp(
          textScale: scale,
          ListView(
            children: [
              Shelf(
                title: 'Continue playing',
                itemCount: games.length,
                itemBuilder: (context, i) => GameCard(game: games[i]),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final card = tester.getSize(find.byType(GameCard).first);
      expect(card.height, GameCard.coverHeight + 8 + 44 * scale);
    });
  }
}
