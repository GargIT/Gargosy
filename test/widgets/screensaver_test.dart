import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/input_action_bus.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/play/play_controller.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/romm_providers.dart';
import 'package:gargosy/ui/shell/screensaver.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

void main() {
  final okami = game(1, 'Okami');

  Future<ProviderContainer> pump(WidgetTester tester, {int? minutes}) async {
    await setDesktopSize(tester);
    final prefs = MemoryPrefs();
    if (minutes != null) await prefs.setString(ScreensaverDelay.prefKey, '$minutes');
    await tester.pumpWidget(
      testApp(
        const IdleScreensaver(child: Scaffold(body: Text('Home'))),
        overrides: [
          appPreferencesProvider.overrideWithValue(prefs),
          libraryApiProvider.overrideWithValue(FakeLibraryApi([okami])),
          rommOfflineProvider.overrideWithValue(false),
        ],
      ),
    );
    return ProviderScope.containerOf(tester.element(find.text('Home')));
  }

  Future<void> wait(WidgetTester tester, Duration d) async {
    await tester.pump(d);
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('after 5 idle minutes it shows the library; a button before that waits again', (tester) async {
    await pump(tester);
    await wait(tester, const Duration(minutes: 4));
    inputActionBus.add(GameAction.down);
    await wait(tester, const Duration(minutes: 4));
    expect(find.byType(ScreensaverScreen), findsNothing, reason: 'the D-pad counted');
    await wait(tester, const Duration(minutes: 1));
    expect(find.byType(ScreensaverScreen), findsOneWidget);
    expect(find.text('Okami'), findsWidgets);

    await press(tester, GameAction.back);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(ScreensaverScreen), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('not while a game runs; never when turned off', (tester) async {
    final c = await pump(tester);
    c.read(playControllerProvider.notifier).state = const PlayState(runningGameId: '1');
    await wait(tester, const Duration(minutes: 6));
    expect(find.byType(ScreensaverScreen), findsNothing);

    await pump(tester, minutes: 0);
    await wait(tester, const Duration(minutes: 40));
    expect(find.byType(ScreensaverScreen), findsNothing);
  });

  testWidgets('A gives back the game shown; any other button only closes it', (tester) async {
    await pump(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    Game? got;
    final shown = nav.push<Game>(MaterialPageRoute(builder: (_) => const ScreensaverScreen()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Okami'), findsWidgets);
    await press(tester, GameAction.confirm);
    got = await shown;
    expect(got?.id, '1');

    final again = nav.push<Game>(MaterialPageRoute(builder: (_) => const ScreensaverScreen()));
    await tester.pump(const Duration(seconds: 2));
    await press(tester, GameAction.detail);
    expect(await again, isNull);
  });
}
