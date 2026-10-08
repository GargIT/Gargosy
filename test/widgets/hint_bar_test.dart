import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/providers/ui_provider.dart';
import 'package:gargosy/ui/widgets/hint_bar.dart';

void main() {
  testWidgets('hints show for controller and keyboard, not mouse', (tester) async {
    final container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: HintBar(hints: [Hint(GameAction.confirm, 'Select'), Hint(GameAction.back, 'Back')]))),
    ));
    expect(find.text('Select'), findsNothing);
    container.read(inputModeProvider.notifier).state = InputMode.gamepad;
    await tester.pump();
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    container.read(inputModeProvider.notifier).state = InputMode.keyboard;
    await tester.pump();
    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
  });
}
