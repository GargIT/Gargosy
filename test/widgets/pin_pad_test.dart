import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/providers/retry.dart';
import 'package:gargosy/ui/input/gargosy_intents.dart';
import 'package:gargosy/ui/widgets/pin_pad.dart';

void main() {
  final entered = <String>[];
  var cancelled = false;

  Future<void> pump(WidgetTester tester, {String? Function(String)? answer}) async {
    entered.clear();
    cancelled = false;
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        child: MaterialApp(
          home: Scaffold(
            body: PinPad(
              title: 'PIN for Anna',
              onComplete: (pin) async {
                entered.add(pin);
                return answer?.call(pin);
              },
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('four digits with the controller complete the PIN', (tester) async {
    await pump(tester);
    // Focus starts on 1; A four times enters 1111.
    for (var i = 0; i < 4; i++) {
      Actions.invoke(FocusManager.instance.primaryFocus!.context!, const ActivateIntent());
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(entered, ['1111']);
  });

  testWidgets('typing digits works and a wrong PIN clears and shows the error', (tester) async {
    await pump(tester, answer: (pin) => pin == '4711' ? null : 'Wrong PIN');
    for (final k in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]) {
      await tester.sendKeyEvent(k);
    }
    await tester.pumpAndSettle();
    expect(entered, ['1234']);
    expect(find.text('Wrong PIN'), findsOneWidget);
    expect(find.byKey(const Key('pin-dot-filled')), findsNothing);
  });

  testWidgets('B deletes a digit, then cancels', (tester) async {
    await pump(tester);
    await tester.tap(find.text('5'));
    await tester.pump();
    expect(find.byKey(const Key('pin-dot-filled')), findsOneWidget);
    Actions.invoke(FocusManager.instance.primaryFocus!.context!, const BackIntent());
    await tester.pump();
    expect(find.byKey(const Key('pin-dot-filled')), findsNothing);
    Actions.invoke(FocusManager.instance.primaryFocus!.context!, const BackIntent());
    expect(cancelled, isTrue);
  });
}
