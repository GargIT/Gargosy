import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/theme/tokens.dart';
import 'package:gargosy/ui/widgets/toast.dart';

import '../helpers/widget_env.dart';

void main() {
  Future<BuildContext> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(const SizedBox.expand(key: ValueKey('page'))));
    return tester.element(find.byKey(const ValueKey('page')));
  }

  testWidgets('a toast shows at the lower right, above the hint bar, and stands out', (tester) async {
    final context = await pump(tester, const Size(1920, 1080));
    showToast(context, 'Okami is downloaded.');
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const ValueKey('toast-box')));
    expect(box.right, closeTo(1920 - GToast.edgeGap, 1));
    expect(box.width, closeTo(GToast.width, 1));
    expect(box.bottom, closeTo(1080 - GSpace.s4 - GToast.hintBarText, 1));
    expect(find.byKey(const ValueKey('toast-info')), findsOneWidget);
  });

  testWidgets('an error is red; a narrow window gives it the width', (tester) async {
    final context = await pump(tester, const Size(400, 700));
    showToast(context, 'Couldn\'t save it.', error: true);
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const ValueKey('toast-box')));
    expect(box.left, closeTo(GToast.edgeGap, 1));
    expect(box.right, closeTo(400 - GToast.edgeGap, 1));
    final icon = tester.widget<Icon>(find.byKey(const ValueKey('toast-error')));
    expect(icon.color, isNot(isNull));
  });

  testWidgets('a window resized while it shows keeps it at the right, its width', (tester) async {
    final context = await pump(tester, const Size(1920, 1080));
    showToast(context, 'Okami is downloaded.');
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1280, 720);
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const ValueKey('toast-box')));
    expect(box.right, closeTo(1280 - GToast.edgeGap, 1));
    expect(box.width, closeTo(GToast.width, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 150 % text it sits higher, above the larger hint bar', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(const SizedBox.expand(key: ValueKey('page')), textScale: 1.5));
    showToast(tester.element(find.byKey(const ValueKey('page'))), 'Okami is downloaded.');
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const ValueKey('toast-box')));
    expect(box.bottom, closeTo(1080 - GSpace.s4 - GToast.hintBarText * 1.5, 1));
  });
}
