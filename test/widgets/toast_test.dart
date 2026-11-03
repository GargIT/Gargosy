import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    final box = tester.getRect(
      find.descendant(of: find.byKey(const ValueKey('toast')), matching: find.byType(Material)).first,
    );
    expect(box.right, closeTo(1920 - toastRight, 1));
    expect(box.width, closeTo(toastWidth, 1));
    expect(box.bottom, closeTo(1080 - toastBottom, 1));
    expect(find.byKey(const ValueKey('toast-info')), findsOneWidget);
  });

  testWidgets('an error is red; a narrow window gives it the width', (tester) async {
    final context = await pump(tester, const Size(400, 700));
    showToast(context, 'Couldn\'t save it.', error: true);
    await tester.pumpAndSettle();
    final box = tester.getRect(
      find.descendant(of: find.byKey(const ValueKey('toast')), matching: find.byType(Material)).first,
    );
    expect(box.left, closeTo(toastRight, 1));
    expect(box.right, closeTo(400 - toastRight, 1));
    final icon = tester.widget<Icon>(find.byKey(const ValueKey('toast-error')));
    expect(icon.color, isNot(isNull));
  });
}
