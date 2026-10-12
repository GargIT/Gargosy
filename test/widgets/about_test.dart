import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/constants/app_constants.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/input_action_bus.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/providers/about_providers.dart';
import 'package:gargosy/ui/input/input_router.dart';
import 'package:gargosy/ui/screens/doc_reader_screen.dart';
import 'package:gargosy/ui/screens/settings/about_section.dart';
import 'package:gargosy/ui/theme/gargosy_theme.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

void main() {
  final opened = <String>[];
  late io.Directory root;

  setUp(() {
    root = io.Directory.systemTemp.createTempSync('gargosy_about');
    io.File(p.join(root.path, 'CHANGELOG.md')).writeAsStringSync(
        '# Changelog\n\n## [0.2.0]\n\n- [Releases](https://github.com/GargIT/Gargosy/releases)\n'
        '- [The notices](NOTICE.md)\n\n${List.generate(80, (i) => 'Line $i of the changes.').join('\n\n')}\n');
    io.File(p.join(root.path, 'NOTICE.md')).writeAsStringSync('# Notices\n\nSee [the 7-Zip licence](LICENSES/7-Zip-LGPL.txt).\n');
    io.File(p.join(root.path, 'LICENSES', '7-Zip-LGPL.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('GNU LESSER GENERAL PUBLIC LICENSE\n  Version 2.1\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> load(WidgetTester tester) => tester.pumpAndSettle();

  Future<void> pump(WidgetTester tester, {String? rommVersion = '4.9.0'}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    opened.clear();
    AppConstants.version = '1.2.3';
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appRootProvider.overrideWithValue(AppRoot(root.path)),
        appPreferencesProvider.overrideWithValue(MemoryPrefs()),
        externalOpenerProvider.overrideWithValue(opened.add),
        rommServerVersionProvider.overrideWith((ref) async => rommVersion),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        theme: gargosyTheme(),
        builder: (context, child) => InputRouter(navigatorKey: nav, startGamepads: false, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(child: TextButton(onPressed: () => showAboutGargosy(context), child: const Text('open'))),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  ScrollPosition readerScroll(WidgetTester tester) =>
      tester.state<ScrollableState>(find.descendant(of: find.byType(DocReaderScreen), matching: find.byType(Scrollable)).first).position;

  testWidgets('the About dialog shows both versions', (tester) async {
    await pump(tester);
    expect(find.text('Gargosy v1.2.3'), findsOneWidget);
    expect(find.text('RomM v4.9.0'), findsOneWidget);
  });

  testWidgets('says so when RomM cannot be asked', (tester) async {
    await pump(tester, rommVersion: null);
    expect(find.text('RomM not reachable'), findsOneWidget);
  });

  testWidgets("A opens What's new at once (it has focus); the changelog shows as Markdown", (tester) async {
    await pump(tester);
    await press(tester, GameAction.confirm);
    await load(tester);
    expect(find.byType(DocReaderScreen), findsOneWidget);
    expect(find.text('CHANGELOG.md'), findsWidgets);
    expect(find.text('Changelog', findRichText: true), findsOneWidget, reason: 'the # heading, without its #');
  });

  testWidgets('B in the reader goes back to the dialog, B again closes it', (tester) async {
    await pump(tester);
    await press(tester, GameAction.confirm);
    await load(tester);
    await press(tester, GameAction.back);
    expect(find.byType(DocReaderScreen), findsNothing);
    expect(find.byType(AboutSection), findsOneWidget);
    await press(tester, GameAction.back);
    expect(find.byType(AboutSection), findsNothing);
  });

  testWidgets('the D-pad scrolls, RB moves a page, and the arrow keys scroll too', (tester) async {
    await pump(tester);
    await press(tester, GameAction.confirm);
    await load(tester);
    final pos = readerScroll(tester);
    expect(pos.pixels, 0);
    inputActionBus.add(GameAction.down);
    await tester.pumpAndSettle();
    final afterDown = pos.pixels;
    expect(afterDown, greaterThan(0));
    await press(tester, GameAction.r1);
    expect(pos.pixels, greaterThan(afterDown + 300));
    final afterPage = pos.pixels;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(pos.pixels, lessThan(afterPage));
  });

  testWidgets('X lists the links: a web link opens outside, a file opens in the reader, a .txt as plain text',
      (tester) async {
    await pump(tester);
    await press(tester, GameAction.confirm);
    await load(tester);

    await press(tester, GameAction.detail);
    await tester.tap(find.text('Releases').last); // the list's, over the text's
    await tester.pumpAndSettle();
    expect(opened.single, 'https://github.com/GargIT/Gargosy/releases');

    await press(tester, GameAction.detail);
    await tester.tap(find.text('The notices').last);
    await load(tester);
    expect(find.text('Notices', findRichText: true), findsOneWidget);

    await press(tester, GameAction.detail);
    await tester.tap(find.text('the 7-Zip licence').last);
    await load(tester);
    expect(find.text('7-Zip-LGPL.txt'), findsOneWidget);
    expect(find.textContaining('GNU LESSER GENERAL PUBLIC LICENSE', findRichText: true), findsOneWidget);
  });

  testWidgets('a file that is not in the Gargosy folder says so', (tester) async {
    await pump(tester);
    await press(tester, GameAction.down);
    await press(tester, GameAction.confirm); // Read me: not in this folder
    await load(tester);
    expect(find.text("README.md isn't in the Gargosy folder."), findsOneWidget);
  });

  testWidgets('the Flutter package licences open in the app; GitHub opens outside', (tester) async {
    await pump(tester);
    await tester.tap(find.text('GitHub'));
    await tester.pump();
    expect(opened.single, 'https://github.com/GargIT/Gargosy');
    await tester.tap(find.text('Dart and Flutter packages'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  test('markdownLinks: inline and reference links in order, no images, anchors or repeats', () {
    const md = '![shot](docs/a.png) See [Releases](https://x/releases "title") and [`NOTICE.md`](NOTICE.md),\n'
        '[top](#top), [Releases again](https://x/releases).\n\n[0.1.0]: https://x/tag/v0.1.0\n';
    expect(markdownLinks(md).map((l) => (l.label, l.href)), [
      ('Releases', 'https://x/releases'),
      ('NOTICE.md', 'NOTICE.md'),
      ('0.1.0', 'https://x/tag/v0.1.0'),
    ]);
  });
}
