import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/download_schedule.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/pin.dart';
import 'package:gargosy/profiles/play_limit.dart';
import 'package:gargosy/profiles/profile.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/screens/settings/play_limit_card.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';

import '../helpers/app_harness.dart';

void main() {
  late AppHarness h;

  Future<Profile> add(WidgetTester tester, String name, {String? pin, PlayLimit limit = PlayLimit.off}) async {
    final store = h.container.read(profileStoreProvider);
    final p = (await tester.runAsync(
      () => store.create(
        name: name,
        colorIndex: 0,
        serverUrl: 'https://romm.example',
        rommUserId: name.length,
        rommUsername: name.toLowerCase(),
        pin: pin == null ? null : PinHash.create(pin, random: Random(3), iterations: 1000),
      ),
    ))!;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    if (!limit.isOn) return p;
    final limited = p.copyWith(playLimit: limit);
    await tester.runAsync(() => store.save(limited));
    return limited;
  }

  Future<void> pump(WidgetTester tester, Profile child) async {
    await tester.runAsync(
      () => h.container
          .read(activeProfileProvider.notifier)
          .activate(child, const ProfileLogin(token: 't', kind: 'device')),
    );
    h.container.invalidate(profilesProvider);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          navigatorKey: nav,
          theme: gargosyTheme(),
          builder: (context, c) => InputRouter(navigatorKey: nav, startGamepads: false, child: c!),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Consumer(
                builder: (context, ref, _) => PlayLimitCard(profile: ref.watch(activeProfileProvider)!.profile),
              ),
            ),
          ),
        ),
      ),
    );
    await h.settle(tester);
  }

  Future<void> choose(WidgetTester tester, String row, String label) async {
    await tester.tap(find.descendant(of: find.byKey(ValueKey(row)), matching: find.text('Change')));
    await h.settle(tester);
    await tester.tap(find.text(label).last);
    await h.settle(tester);
  }

  PlayLimit saved() => h.container.read(activeProfileProvider)!.profile.playLimit;

  testWidgets("minutes a day and hours, each changed only with a parent's PIN", (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    await add(tester, 'Parent', pin: '4711');
    final kid = await add(tester, 'Kid');
    await pump(tester, kid);
    expect(find.text('No limit'), findsOneWidget);
    expect(find.text('Any time'), findsOneWidget);
    await choose(tester, 'play-limit-minutes', '1 h a day');
    expect(find.text('PIN for Parent'), findsOneWidget);
    for (final k in const [
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit1,
    ]) {
      await tester.sendKeyEvent(k);
    }
    await h.settle(tester);
    expect(saved(), const PlayLimit(minutesPerDay: 60));
    await choose(tester, 'play-limit-window', '15:00–20:00');
    expect(find.text('PIN for Parent'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle(tester);
    expect(saved().window, isNull, reason: 'no PIN, no change');
    expect(saved(), isNot(const PlayLimit(minutesPerDay: 60, window: DownloadWindow(900, 1200))));
  });
}
