import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/input_action_bus.dart';
import 'package:gargosy/providers/ui_provider.dart';
import 'package:gargosy/ui/input/gargosy_intents.dart';
import 'package:gargosy/ui/input/input_router.dart';

void main() {
  late GlobalKey<NavigatorState> nav;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, Widget home) async {
    nav = GlobalKey<NavigatorState>();
    container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => InputRouter(navigatorKey: nav, startGamepads: false, child: child!),
        home: home,
      ),
    ));
  }

  Future<void> send(WidgetTester tester, GameAction a) async {
    inputActionBus.add(a);
    await tester.pump();
  }

  testWidgets('A activates the focused button', (tester) async {
    var pressed = 0;
    await pump(tester, Scaffold(body: TextButton(autofocus: true, onPressed: () => pressed++, child: const Text('Go'))));
    await tester.pump();
    await send(tester, GameAction.confirm);
    expect(pressed, 1);
  });

  testWidgets('X, Y, LB, RB, Start and A held reach the focused widget\'s actions', (tester) async {
    final seen = <Type>[];
    Action<T> record<T extends Intent>() => CallbackAction<T>(onInvoke: (i) => seen.add(T));
    await pump(
      tester,
      Scaffold(
        body: Actions(
          actions: {
            DetailIntent: record<DetailIntent>(),
            FavoriteIntent: record<FavoriteIntent>(),
            PrevTabIntent: record<PrevTabIntent>(),
            NextTabIntent: record<NextTabIntent>(),
            MenuIntent: record<MenuIntent>(),
            LongActivateIntent: record<LongActivateIntent>(),
          },
          child: const Focus(autofocus: true, child: SizedBox()),
        ),
      ),
    );
    await tester.pump();
    for (final a in [GameAction.detail, GameAction.favorite, GameAction.l1, GameAction.r1, GameAction.start, GameAction.confirmHold]) {
      await send(tester, a);
    }
    expect(seen, [DetailIntent, FavoriteIntent, PrevTabIntent, NextTabIntent, MenuIntent, LongActivateIntent]);
  });

  testWidgets('B pops the route when nothing handles BackIntent', (tester) async {
    await pump(tester, const Scaffold(body: Text('home')));
    nav.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Focus(autofocus: true, child: Text('second')))));
    await tester.pumpAndSettle();
    await send(tester, GameAction.back);
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a screen that handles BackIntent itself is not popped', (tester) async {
    var backs = 0;
    await pump(tester, const Scaffold(body: Text('home')));
    nav.currentState!.push(MaterialPageRoute(
        builder: (_) => Actions(
              actions: {BackIntent: CallbackAction<BackIntent>(onInvoke: (_) => backs++)},
              child: const Focus(autofocus: true, child: Text('second')),
            )));
    await tester.pumpAndSettle();
    await send(tester, GameAction.back);
    await tester.pumpAndSettle();
    expect(backs, 1);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('Escape is back on the keyboard; keys set keyboard mode, a click sets mouse mode', (tester) async {
    await pump(tester, const Scaffold(body: Text('home')));
    nav.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Focus(autofocus: true, child: Text('second')))));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
    expect(container.read(inputModeProvider), InputMode.keyboard);
    await tester.tap(find.text('home'));
    await tester.pump();
    expect(container.read(inputModeProvider), InputMode.mouse);
  });
}
