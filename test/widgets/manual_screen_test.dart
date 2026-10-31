import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/core/input/input_action_bus.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/game_manual.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/providers/download_providers.dart';
import 'package:gargosy/ui/screens/manual/manual_document.dart';
import 'package:gargosy/ui/screens/manual/manual_screen.dart';

import '../helpers/game_fixtures.dart';
import '../helpers/widget_env.dart';

class _Doc implements ManualDocument {
  _Doc(this.pageCount, {this.shape = const Size(1600, 900)});
  @override
  final int pageCount;
  final Size shape;
  var disposed = false;

  @override
  Size pageSize(int index) => shape;

  @override
  Widget page(int index) => ColoredBox(key: ValueKey('fake-page-$index'), color: Colors.white);

  @override
  Future<void> dispose() async => disposed = true;
}

class _Manuals extends GameManuals {
  _Manuals({this.problem, this.kept = false})
    : super(guard: PathGuard(AppRoot(r'C:\nowhere')), dir: r'C:\nowhere\manuals');
  final String? problem;
  bool kept;
  var forgotten = 0;

  @override
  bool isKept(Game game) => kept;

  @override
  Future<String> open(Game game) async {
    if (problem != null) throw ManualUnavailable(problem!);
    kept = true;
    return r'C:\nowhere\manuals\1.pdf';
  }

  @override
  Future<void> forget(Game game) async {
    forgotten++;
    kept = false;
  }
}

void main() {
  final game = Game.fromJson({...gameJson(1, 'Chrono Trigger'), 'path_manual': 'roms/1/manual/1.pdf'});

  Future<_Doc> show(
    WidgetTester tester, {
    int pages = 3,
    String? problem,
    Size shape = const Size(1600, 900),
    _Manuals? manuals,
    Future<ManualDocument> Function(String path)? opener,
  }) async {
    final doc = _Doc(pages, shape: shape);
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        ManualScreen(game: game),
        overrides: [
          gameManualsProvider.overrideWithValue(manuals ?? _Manuals(problem: problem)),
          manualOpenerProvider.overrideWithValue(opener ?? (_) async => doc),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return doc;
  }

  /// A D-pad step through the bus, as GamepadService sends it while nothing
  /// else takes focus; it lands after the frame it's sent in.
  Future<void> dpad(WidgetTester tester, GameAction a, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      inputActionBus.add(a);
    }
    await tester.pump();
    await tester.pump();
  }

  Matrix4 view(WidgetTester tester) =>
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!.value;

  testWidgets('a page at a time; LB/RB and Page Up/Down turn, not past either end', (tester) async {
    await show(tester);
    expect(find.byKey(const ValueKey('fake-page-0')), findsOneWidget);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    await press(tester, GameAction.r1);
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-page-1')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    await press(tester, GameAction.r1);
    await tester.pump();
    expect(find.text('Page 3 of 3'), findsOneWidget);
    await press(tester, GameAction.l1);
    await tester.pump();
    expect(find.text('Page 2 of 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(find.text('Page 1 of 3'), findsOneWidget);
  });

  testWidgets('A zooms in steps and back; the D-pad turns a whole page, pans a zoomed one; X fits it', (tester) async {
    await show(tester);
    await dpad(tester, GameAction.right);
    expect(find.text('Page 2 of 3'), findsOneWidget);

    await press(tester, GameAction.confirm);
    await tester.pump();
    expect(view(tester).getMaxScaleOnAxis(), 1.5);
    final before = view(tester).getTranslation();
    await dpad(tester, GameAction.right);
    expect(find.text('Page 2 of 3'), findsOneWidget, reason: 'zoomed, the D-pad pans');
    expect(view(tester).getTranslation().x, lessThan(before.x));
    // Never past the page's edge.
    await dpad(tester, GameAction.down, 20);
    final t = view(tester).getTranslation();
    expect(t.y, lessThan(0));
    await dpad(tester, GameAction.down);
    expect(view(tester).getTranslation().y, t.y, reason: 'clamped at the bottom edge of the page');

    await press(tester, GameAction.confirm);
    await press(tester, GameAction.confirm);
    await tester.pump();
    expect(view(tester).getMaxScaleOnAxis(), 3.0);
    await press(tester, GameAction.confirm);
    await tester.pump();
    expect(view(tester).getMaxScaleOnAxis(), 1.0, reason: 'after the last step, the whole page');

    await press(tester, GameAction.confirm);
    await press(tester, GameAction.detail);
    await tester.pump();
    expect(view(tester).getMaxScaleOnAxis(), 1.0);
  });

  testWidgets('a zoomed page narrower than the screen stays centred: left/right still turn, up/down pan', (
    tester,
  ) async {
    await show(tester, shape: const Size(600, 800));
    await press(tester, GameAction.confirm);
    await tester.pump();
    final centred = view(tester).getTranslation().x;
    await dpad(tester, GameAction.right);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(view(tester).getMaxScaleOnAxis(), 1.0, reason: 'a new page starts whole');
    await press(tester, GameAction.confirm);
    await tester.pump();
    expect(view(tester).getTranslation().x, centred);
    final y = view(tester).getTranslation().y;
    await dpad(tester, GameAction.down);
    expect(view(tester).getTranslation().y, lessThan(y));
    expect(view(tester).getTranslation().x, centred);
  });

  testWidgets('A while the manual is still coming does nothing to the page it opens on', (tester) async {
    final coming = Completer<ManualDocument>();
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        ManualScreen(game: game),
        overrides: [
          gameManualsProvider.overrideWithValue(_Manuals()),
          manualOpenerProvider.overrideWithValue((_) => coming.future),
        ],
      ),
    );
    await tester.pump();
    // The spinner never settles: A goes straight onto the bus.
    inputActionBus.add(GameAction.confirm);
    await tester.pump();
    await tester.pump();
    coming.complete(_Doc(3));
    await tester.pumpAndSettle();
    expect(view(tester).getMaxScaleOnAxis(), 1.0);
  });

  testWidgets("a kept copy PDFium can't open is fetched again, once", (tester) async {
    final manuals = _Manuals(kept: true);
    var tries = 0;
    await show(
      tester,
      manuals: manuals,
      opener: (_) async {
        if (tries++ == 0) throw StateError('damaged');
        return _Doc(2);
      },
    );
    expect(manuals.forgotten, 1);
    expect(find.text('Page 1 of 2'), findsOneWidget);
  });

  testWidgets("why a manual can't be shown is said", (tester) async {
    await show(tester, problem: "RomM didn't send the manual.");
    expect(find.text("RomM didn't send the manual."), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('the document is closed with the page', (tester) async {
    final doc = await show(tester);
    await tester.pumpWidget(const SizedBox());
    expect(doc.disposed, isTrue);
  });
}
