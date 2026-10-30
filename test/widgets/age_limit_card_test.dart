import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/age_limit.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/pin.dart';
import 'package:gargosy/profiles/profile.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/screens/settings/age_limit_card.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';

import '../helpers/app_harness.dart';

void main() {
  late AppHarness h;

  Future<Profile> add(WidgetTester tester, String name, {String? pin, AgeLimit limit = AgeLimit.off}) async {
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
    if (!limit.isOn) return p;
    final limited = p.copyWith(ageLimit: limit);
    await tester.runAsync(() => store.save(limited));
    return limited;
  }

  /// The card of [child], open as the active profile.
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
                builder: (context, ref, _) => AgeLimitCard(profile: ref.watch(activeProfileProvider)!.profile),
              ),
            ),
          ),
        ),
      ),
    );
    await h.settle(tester);
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.text('Change'));
    await h.settle(tester);
    await tester.tap(find.text(label));
    await h.settle(tester);
  }

  Future<void> typePin(WidgetTester tester, List<LogicalKeyboardKey> keys) async {
    for (final k in keys) {
      await tester.sendKeyEvent(k);
    }
    await h.settle(tester);
  }

  AgeLimit saved() => h.container.read(activeProfileProvider)!.profile.ageLimit;

  testWidgets('with no PIN anywhere it changes at once, and says anyone can', (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    final kid = await add(tester, 'Kid');
    await pump(tester, kid);
    expect(find.textContaining('Anyone can change it'), findsOneWidget);
    await choose(tester, 'Up to 12');
    expect(saved(), const AgeLimit(maxAge: 12));
    expect(find.text('Hide unrated games'), findsOneWidget);
  });

  testWidgets("a parent's PIN is asked: a wrong one keeps the limit, the right one changes it", (tester) async {
    h = AppHarness();
    await h.setUp(tester);
    await add(tester, 'Parent', pin: '4711');
    final kid = await add(tester, 'Kid', pin: '1234', limit: const AgeLimit(maxAge: 7));
    await pump(tester, kid);
    expect(find.textContaining('Anyone can change it'), findsNothing);
    await choose(tester, 'Off');
    expect(find.text('PIN for Parent'), findsOneWidget, reason: "the parent's, not the child's own");
    await typePin(tester, const [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]);
    expect(find.text('Wrong PIN'), findsOneWidget);
    expect(saved(), const AgeLimit(maxAge: 7));
    await typePin(tester, const [
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit1,
    ]);
    expect(saved(), AgeLimit.off);
  });

  test('guardians: other profiles without a limit that have a PIN', () {
    Profile p(String id, {bool pin = false, AgeLimit limit = AgeLimit.off}) => Profile(
      id: id,
      name: id,
      colorIndex: 0,
      serverUrl: 's',
      rommUserId: 1,
      rommUsername: id,
      createdAt: DateTime(2026),
      pin: pin ? PinHash.create('1234', random: Random(1), iterations: 1) : null,
      ageLimit: limit,
    );
    final kid = p('kid', pin: true, limit: const AgeLimit(maxAge: 7));
    final mum = p('mum', pin: true), dad = p('dad'), sib = p('sib', pin: true, limit: const AgeLimit(maxAge: 12));
    expect(guardiansOf([kid, mum, dad, sib], kid), [mum]);
  });
}
