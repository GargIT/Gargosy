import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/constants/app_constants.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/about_providers.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/screens/about_screen.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';

import '../helpers/widget_env.dart';

void main() {
  final opened = <String>[];

  Future<void> pump(WidgetTester tester, {String? rommVersion = '4.9.0'}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    opened.clear();
    AppConstants.version = '1.2.3';
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appRootProvider.overrideWithValue(AppRoot('/gargosy')),
        externalOpenerProvider.overrideWithValue(opened.add),
        rommServerVersionProvider.overrideWith((ref) async => rommVersion),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        theme: gargosyTheme(),
        builder: (context, child) => InputRouter(navigatorKey: nav, startGamepads: false, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows both versions', (tester) async {
    await pump(tester);
    expect(find.text('v1.2.3'), findsOneWidget);
    expect(find.text('v4.9.0'), findsOneWidget);
  });

  testWidgets('says so when RomM cannot be asked', (tester) async {
    await pump(tester, rommVersion: null);
    expect(find.text('Not reachable'), findsOneWidget);
  });

  testWidgets('links open the repository pages', (tester) async {
    await pump(tester);
    for (final (label, url) in [
      ('Repository', 'https://github.com/GargIT/Gargosy'),
      ('Releases', 'https://github.com/GargIT/Gargosy/releases'),
      ('Report a bug', 'https://github.com/GargIT/Gargosy/issues'),
      ('Security policy', 'https://github.com/GargIT/Gargosy/blob/main/SECURITY.md'),
      ('Changelog', 'https://github.com/GargIT/Gargosy/blob/main/CHANGELOG.md'),
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pump();
      expect(opened.last, url, reason: label);
    }
  });

  testWidgets('licence files open from the Gargosy folder; Flutter licences in app', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.text('NOTICE.md'));
    await tester.tap(find.text('NOTICE.md'));
    await tester.pump();
    expect(opened.single, endsWith('NOTICE.md'));
    await tester.ensureVisible(find.text('Dart and Flutter packages'));
    await tester.tap(find.text('Dart and Flutter packages'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('a controller can focus a row, press A and go back with B', (tester) async {
    await pump(tester);
    await press(tester, GameAction.down);
    await press(tester, GameAction.confirm);
    expect(opened, isNotEmpty);
    await press(tester, GameAction.back);
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsNothing);
  });
}
