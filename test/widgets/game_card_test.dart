import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/ui/widgets/game_card.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

void main() {
  testWidgets('shows the cover and the name; A opens, Y favourites', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(testApp(Center(
      child: GameCard(
        game: game(1, 'Burnout 3'),
        coverUrl: 'https://romm.example/c.png',
        autofocus: true,
        onOpen: () => calls.add('open'),
        onFavorite: () => calls.add('fav'),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Burnout 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('cover:https://romm.example/c.png')), findsOneWidget);
    await press(tester, GameAction.confirm);
    await press(tester, GameAction.favorite);
    expect(calls, ['open', 'fav']);
  });

  testWidgets('marks downloaded and favourite games; no cover shows the title on art', (tester) async {
    await tester.pumpWidget(testApp(Center(child: GameCard(game: game(1, 'Okami'), downloaded: true, favourite: true))));
    expect(find.byIcon(Icons.download_done), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('Okami'), findsNWidgets(2));
  });
}
