import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/input/gargosy_intents.dart';
import 'package:gargosy/ui/widgets/on_screen_keyboard.dart';

void main() {
  String? done;
  var cancelled = false;

  Future<void> pump(WidgetTester tester, {String initial = '', bool obscure = false}) async {
    done = null;
    cancelled = false;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: OnScreenKeyboard(
            key: UniqueKey(), // a fresh keyboard each pump, even within one test
            title: 'Server',
            initial: initial,
            obscure: obscure,
            onDone: (v) => done = v,
            onCancel: () => cancelled = true,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  BuildContext focused() => FocusManager.instance.primaryFocus!.context!;

  testWidgets('pressing keys builds the text; Done returns it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('r'));
    await tester.tap(find.text('o'));
    await tester.tap(find.text('.'));
    await tester.tap(find.text('Done'));
    expect(done, 'ro.');
  });

  testWidgets('the first key has focus and A presses it', (tester) async {
    await pump(tester);
    Actions.invoke(focused(), const ActivateIntent());
    await tester.pump();
    expect(find.text('1'), findsWidgets);
    await tester.tap(find.text('Done'));
    expect(done, '1');
  });

  testWidgets('B deletes, then cancels when empty', (tester) async {
    await pump(tester, initial: 'ab');
    Actions.invoke(focused(), const BackIntent());
    await tester.pump();
    await tester.tap(find.text('Done'));
    expect(done, 'a');
    await pump(tester);
    Actions.invoke(focused(), const BackIntent());
    expect(cancelled, isTrue);
  });

  testWidgets('X adds a space and Start is Done', (tester) async {
    await pump(tester, initial: 'a');
    Actions.invoke(focused(), const DetailIntent());
    Actions.invoke(focused(), const MenuIntent());
    expect(done, 'a ');
  });

  testWidgets('a physical keyboard types, deletes and submits', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH, character: 'h');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(done, 'h');
  });

  testWidgets('shift switches letters to capitals', (tester) async {
    await pump(tester);
    await tester.tap(find.text('⇧'));
    await tester.pump();
    await tester.tap(find.text('A'));
    await tester.tap(find.text('Done'));
    expect(done, 'A');
  });

  testWidgets('an obscured field shows dots, not the text', (tester) async {
    await pump(tester, initial: 'secret', obscure: true);
    expect(find.text('secret'), findsNothing);
    expect(find.text('••••••'), findsOneWidget);
  });
}
