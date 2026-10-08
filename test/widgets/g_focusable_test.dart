import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/providers/ui_provider.dart';
import 'package:gargosy/ui/input/gargosy_intents.dart';
import 'package:gargosy/ui/widgets/g_focusable.dart';

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, Widget child) async {
    container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: Scaffold(body: Center(child: child)))));
    await tester.pump();
  }

  testWidgets('ActivateIntent, a tap, LongActivateIntent and DetailIntent call their callbacks', (tester) async {
    final calls = <String>[];
    final node = FocusNode();
    await pump(
        tester,
        GFocusable(
          focusNode: node,
          autofocus: true,
          onActivate: () => calls.add('a'),
          onLongActivate: () => calls.add('long'),
          onDetail: () => calls.add('x'),
          child: const SizedBox(width: 50, height: 50),
        ));
    Actions.invoke(node.context!, const ActivateIntent());
    Actions.invoke(node.context!, const LongActivateIntent());
    Actions.invoke(node.context!, const DetailIntent());
    await tester.tap(find.byType(GFocusable));
    expect(calls, ['a', 'long', 'x', 'a']);
  });

  testWidgets('the focus ring shows for controller focus, not in mouse mode', (tester) async {
    await pump(tester, const GFocusable(autofocus: true, child: SizedBox(width: 50, height: 50)));
    expect(find.byKey(GFocusable.ringKey), findsNothing);
    container.read(inputModeProvider.notifier).state = InputMode.gamepad;
    await tester.pump();
    expect(find.byKey(GFocusable.ringKey), findsOneWidget);
  });

  testWidgets('D-pad focus moves between GFocusables by direction', (tester) async {
    final left = FocusNode(), right = FocusNode();
    await pump(
        tester,
        Row(mainAxisSize: MainAxisSize.min, children: [
          GFocusable(focusNode: left, autofocus: true, child: const SizedBox(width: 50, height: 50)),
          const SizedBox(width: 20),
          GFocusable(focusNode: right, child: const SizedBox(width: 50, height: 50)),
        ]));
    left.focusInDirection(TraversalDirection.right);
    await tester.pump();
    expect(right.hasPrimaryFocus, isTrue);
  });
}
