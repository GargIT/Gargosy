import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/audio/ui_sound_service.dart';
import 'package:gargosy/core/audio/ui_sounds.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/platform/sound_player.dart';
import 'package:gargosy/providers/retry.dart';
import 'package:gargosy/providers/sound_providers.dart';
import 'package:gargosy/providers/ui_provider.dart';
import 'package:gargosy/ui/input/gargosy_intents.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/widgets/toast.dart';

import '../helpers/widget_env.dart' show press;

/// Which sound each WAV is, by making them all once.
final _names = {for (final s in UiSound.values) s: uiSoundWav(s, 0.5)};

class _Heard implements SoundPlayer {
  final played = <UiSound>[];

  @override
  void play(Uint8List wav) {
    played.add(_names.entries.firstWhere((e) => _same(e.value, wav)).key);
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

void main() {
  late _Heard heard;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, Widget home, {bool on = true}) async {
    heard = _Heard();
    final nav = GlobalKey<NavigatorState>();
    container = ProviderContainer(
      retry: noRetry,
      overrides: [
        uiSoundsProvider.overrideWithValue(UiSoundService(heard, on: on, volume: 50, gameRunning: () => false)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: nav,
          builder: (context, child) => InputRouter(navigatorKey: nav, startGamepads: false, child: child!),
          home: Scaffold(body: home),
        ),
      ),
    );
    await tester.pump();
  }

  Widget buttons({VoidCallback? onTab}) => Actions(
    actions: {if (onTab != null) NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) => onTab())},
    child: Column(
      children: [
        TextButton(autofocus: true, onPressed: () {}, child: const Text('one')),
        TextButton(onPressed: () {}, child: const Text('two')),
      ],
    ),
  );

  testWidgets('A, B and RB play their sounds; a tab nobody takes stays quiet', (tester) async {
    await pump(tester, buttons());
    await press(tester, GameAction.confirm);
    await press(tester, GameAction.back);
    await press(tester, GameAction.r1);
    expect(heard.played, [UiSound.open, UiSound.back]);

    var tabs = 0;
    await pump(tester, buttons(onTab: () => tabs++));
    await press(tester, GameAction.r1);
    expect(tabs, 1);
    expect(heard.played, [UiSound.tab]);
  });

  testWidgets('a focus moved with the controller is heard, one moved by the mouse is not', (tester) async {
    await pump(tester, buttons());
    container.read(inputModeProvider.notifier).state = InputMode.gamepad;
    await press(tester, GameAction.down);
    expect(heard.played, [UiSound.move]);

    container.read(inputModeProvider.notifier).state = InputMode.mouse;
    await press(tester, GameAction.up);
    expect(heard.played, [UiSound.move]);
  });

  testWidgets('off: nothing is heard', (tester) async {
    await pump(tester, buttons(), on: false);
    container.read(inputModeProvider.notifier).state = InputMode.gamepad;
    await press(tester, GameAction.confirm);
    await press(tester, GameAction.down);
    expect(heard.played, isEmpty);
  });

  testWidgets('an error toast plays the error sound; another toast none', (tester) async {
    await pump(tester, const SizedBox());
    final context = tester.element(find.byType(SizedBox));
    showToast(context, 'Saved.');
    showToast(context, 'Couldn\'t save it.', error: true);
    await tester.pump();
    expect(heard.played, [UiSound.error]);
  });
}
