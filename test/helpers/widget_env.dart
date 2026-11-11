import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/providers/retry.dart';

import 'overrides.dart';

import 'package:gargosy/ui/widgets/platform_logo.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/input_action_bus.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';
import 'package:gargosy/ui/pages/home/home_reveal.dart';
import 'package:gargosy/ui/widgets/baked_art.dart';
import 'package:gargosy/ui/widgets/cover_image.dart';

/// [child] in Gargosy's app frame (theme, controller input), with covers
/// drawn as plain boxes so no test touches the network. Without [root] the
/// Gargosy folder is one that doesn't exist: nothing is downloaded there and
/// nothing may be written.
Widget testApp(
  Widget child, {
  List<Override> overrides = const [],
  GlobalKey<NavigatorState>? navigatorKey,
  AppRoot? root,
  double? textScale,
}) {
  final scale = textScale ?? _hunt;
  final nav = navigatorKey ?? GlobalKey<NavigatorState>();
  return ProviderScope(
    retry: noRetry,
    overrides: lastWins([
      coverImageBuilderProvider.overrideWithValue((url) => ColoredBox(key: ValueKey('cover:$url'), color: Colors.grey)),
      artImageProvider.overrideWithValue((url) => null),
      homeRevealStepProvider.overrideWithValue(Duration.zero),
      platformLogoBuilderProvider.overrideWithValue((url, size, fallback) => fallback),
      appRootProvider.overrideWithValue(root ?? AppRoot(r'C:\gargosy-tests-nowhere')),
      ...overrides,
    ]),
    child: MaterialApp(
      navigatorKey: nav,
      theme: gargosyTheme(),
      builder: (context, c) => InputRouter(
        navigatorKey: nav,
        startGamepads: false,
        child: scale == null
            ? c!
            : MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: c!,
              ),
      ),
      home: Scaffold(body: child),
    ),
  );
}

/// #240: `flutter test test/widgets --dart-define=GARGOSY_TEXT_150=1` runs
/// every test framed by [testApp] at 150 % text, and [setDesktopSize] at
/// 1280 × 720: what overflows there is a layout to fix (some tests fail for
/// other reasons then: a text scrolled out of view, a narrower window).
final double? _hunt = const String.fromEnvironment('GARGOSY_TEXT_150').isEmpty ? null : 1.5;

Future<void> setDesktopSize(WidgetTester tester) async {
  tester.view.physicalSize = _hunt == null ? const Size(1920, 1080) : const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A controller button. The D-pad moves focus the way GamepadService does
/// (which isn't started in tests); the rest goes through the action bus.
Future<void> press(WidgetTester tester, GameAction a) async {
  const directions = {
    GameAction.up: TraversalDirection.up,
    GameAction.down: TraversalDirection.down,
    GameAction.left: TraversalDirection.left,
    GameAction.right: TraversalDirection.right,
  };
  final dir = directions[a];
  if (dir != null) {
    if (FocusManager.instance.primaryFocus?.focusInDirection(dir) ?? false) focusMovedBus.add(null);
  } else {
    inputActionBus.add(a);
  }
  await tester.pumpAndSettle();
}
