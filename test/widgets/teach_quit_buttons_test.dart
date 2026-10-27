import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/held_combo.dart';
import 'package:gargosy/core/input/hid_buttons.dart';
import 'package:gargosy/core/input/hid_pads.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/screens/settings/teach_quit_buttons.dart';

import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

class _Reader implements BackgroundPads {
  _Reader(this.onRaw, this.onDevices);
  final void Function(HidDevice, Set<int>) onRaw;
  final void Function(List<HidDevice>, bool) onDevices;
  var started = false;
  var stopped = false;
  @override
  void start() => started = true;
  @override
  void stop() => stopped = true;
}

class _Device implements HidDevice {
  _Device(this.vendor, this.product);
  @override
  final int vendor;
  @override
  final int product;
  @override
  String get name => 'Odd Pad';
  @override
  bool get gone => false;
  @override
  Set<int>? poll() => null;
  @override
  void close() {}
}

void main() {
  late MemoryPrefs prefs;
  late _Reader reader;
  bool? result;

  Future<void> open(WidgetTester tester) async {
    prefs = MemoryPrefs();
    result = null;
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showTeachQuitButtons(context),
            child: const Text('open'),
          ),
        ),
        overrides: [
          appPreferencesProvider.overrideWithValue(prefs),
          hidTeachReaderProvider.overrideWithValue((onRaw, onDevices) => reader = _Reader(onRaw, onDevices)),
        ],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, HidDevice device, int button) async {
    reader.onRaw(device, {button});
    await tester.pump();
    reader.onRaw(device, const {});
    await tester.pump();
  }

  testWidgets('each button pressed once is kept for that controller', (tester) async {
    await open(tester);
    expect(reader.started, isTrue);
    expect(find.textContaining('Looking for controllers'), findsOneWidget);
    expect(find.textContaining('Press Select'), findsOneWidget);
    final pad = _Device(0x1234, 0xabcd);
    reader.onDevices([pad], false);
    await tester.pump();
    expect(find.textContaining('Hears Odd Pad.'), findsOneWidget);
    await tap(tester, pad, 8);
    expect(find.textContaining('Teaching Odd Pad (1234:abcd)'), findsOneWidget);
    expect(find.textContaining('Press Start'), findsOneWidget);

    await tap(tester, pad, 8);
    expect(find.textContaining('already Select'), findsOneWidget, reason: 'one button, one job');
    expect(find.textContaining('Press Start'), findsOneWidget);

    await tap(tester, _Device(0x9999, 1), 9);
    expect(find.textContaining('Press Start'), findsOneWidget, reason: 'another controller is not listened to');

    await tap(tester, pad, 9);
    await tap(tester, pad, 4);
    await tap(tester, pad, 5);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tap(tester, pad, 11);
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved for Odd Pad: 5 of 6'), findsOneWidget);
    expect(LearnedHidButtons.read(prefs), {
      '1234:abcd': {8: PadButton.select, 9: PadButton.start, 4: PadButton.l1, 5: PadButton.r1, 11: PadButton.r3},
    });

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(reader.stopped, isTrue);
  });

  testWidgets('it says when only Xbox controllers, or none, are connected', (tester) async {
    await open(tester);
    reader.onDevices(const [], true);
    await tester.pump();
    expect(find.textContaining('Only Xbox (XInput) controllers are connected'), findsOneWidget);
    reader.onDevices(const [], false);
    await tester.pump();
    expect(find.textContaining('No controller found'), findsOneWidget);
  });

  testWidgets("the controller's B is taught, not Back; Escape cancels", (tester) async {
    await open(tester);
    await press(tester, GameAction.back);
    await press(tester, GameAction.confirm);
    expect(find.textContaining('Press Select'), findsOneWidget, reason: 'still open');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.textContaining('Press Start'), findsOneWidget, reason: 'Enter skips');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('Press'), findsNothing);
    expect(result, isFalse);
    expect(prefs.getString(LearnedHidButtons.prefKey), isNull);
  });
}
