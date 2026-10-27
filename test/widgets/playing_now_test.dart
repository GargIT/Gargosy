import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_activity.dart';
import 'package:gargosy/providers/library_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/pages/home/playing_now.dart';

import '../helpers/widget_env.dart';

void main() {
  ActivityEntry entry(int user, String game, {String client = 'Gargosy'}) => ActivityEntry(
    userId: user,
    username: 'Player $user',
    gameId: '${40 + user}',
    gameName: game,
    platformName: 'Super Nintendo',
    deviceId: 'dev$user',
    client: client,
    startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 25)),
  );

  testWidgets('Playing now (#180): a card a player, "You" for this profile', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(
      testApp(
        const SingleChildScrollView(child: PlayingNowRow()),
        overrides: [
          playingNowProvider.overrideWith((ref) async => [entry(1, 'Super Metroid'), entry(7, 'Kirby', client: 'web')]),
          rommUserIdProvider.overrideWithValue(7),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Playing now'), findsOneWidget);
    expect(find.text('Player 1 · Super Nintendo'), findsOneWidget);
    expect(find.text('You · Super Nintendo'), findsOneWidget);
    expect(find.text('on Gargosy · for 25 min'), findsOneWidget);
    expect(find.text("in RomM's web UI · for 25 min"), findsOneWidget);
  });

  testWidgets('nobody playing: no row', (tester) async {
    await tester.pumpWidget(
      testApp(
        const SingleChildScrollView(child: PlayingNowRow()),
        overrides: [playingNowProvider.overrideWith((ref) async => const [])],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Playing now'), findsNothing);
  });
}
