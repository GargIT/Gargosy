import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/widgets/platform_logo.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/input_action_bus.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';
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
}) {
  final nav = navigatorKey ?? GlobalKey<NavigatorState>();
  return ProviderScope(
    overrides: [
      coverImageBuilderProvider.overrideWithValue((url) => ColoredBox(key: ValueKey('cover:$url'), color: Colors.grey)),
      platformLogoBuilderProvider.overrideWithValue((url, size, fallback) => fallback),
      appRootProvider.overrideWithValue(root ?? AppRoot(r'C:\gargosy-tests-nowhere')),
      ...overrides,
    ],
    child: MaterialApp(
      navigatorKey: nav,
      theme: gargosyTheme(),
      builder: (context, c) => InputRouter(navigatorKey: nav, startGamepads: false, child: c!),
      home: Scaffold(body: child),
    ),
  );
}

Future<void> setDesktopSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
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
    FocusManager.instance.primaryFocus?.focusInDirection(dir);
  } else {
    inputActionBus.add(a);
  }
  await tester.pumpAndSettle();
}
