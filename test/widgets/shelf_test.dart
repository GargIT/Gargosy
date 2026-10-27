import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/input/gamepad_service.dart';
import 'package:gargosy/ui/widgets/g_focusable.dart';
import 'package:gargosy/ui/widgets/shelf.dart';

import '../helpers/widget_env.dart';

void main() {
  test('as many as fit; See all takes the last place only when they do not all fit', () {
    // 100 wide with a 16 gap: 4 places in 448.
    expect(Shelf.fit(width: 448, itemWidth: 100, count: 10, seeAll: true), (3, true));
    expect(Shelf.fit(width: 448, itemWidth: 100, count: 10, seeAll: false), (4, false));
    expect(Shelf.fit(width: 448, itemWidth: 100, count: 3, seeAll: true), (3, true));
    expect(Shelf.fit(width: 448, itemWidth: 100, count: 4, seeAll: true), (3, true));
    expect(Shelf.fit(width: 448, itemWidth: 100, count: 2, seeAll: false), (2, false));
    expect(Shelf.fit(width: 50, itemWidth: 100, count: 5, seeAll: true), (0, true));
  });

  Widget shelf(int count, {VoidCallback? onSeeAll}) => SingleChildScrollView(
    child: Shelf(
      title: 'Recently added',
      itemCount: count,
      itemWidth: 100,
      height: 100,
      seeAllSize: const Size(100, 100),
      onSeeAll: onSeeAll,
      itemBuilder: (context, i) =>
          GFocusable(key: ValueKey('item-$i'), onActivate: () {}, child: const SizedBox(width: 100, height: 100)),
    ),
  );

  testWidgets('a row (#184) shows what fits, See all last, and nothing scrolls sideways', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var opened = false;
    await tester.pumpWidget(testApp(shelf(40, onSeeAll: () => opened = true)));
    await tester.pumpAndSettle();
    final shown = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && '${(w.key as ValueKey).value}'.startsWith('item-'),
    );
    final n = tester.widgetList(shown).length;
    expect(n, inInclusiveRange(5, 39));
    expect(find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right), findsNothing);
    final seeAll = tester.getRect(find.byKey(const ValueKey('see-all')));
    expect(seeAll.right, lessThanOrEqualTo(1280));
    expect(seeAll.left, greaterThan(tester.getRect(find.byKey(ValueKey('item-${n - 1}'))).right));

    // Along the row with the D-pad to See all.
    Focus.of(
      tester.element(find.descendant(of: find.byKey(const ValueKey('item-0')), matching: find.byType(SizedBox)).first),
    ).requestFocus();
    await tester.pumpAndSettle();
    for (var i = 0; i < n; i++) {
      await press(tester, GameAction.right);
    }
    await press(tester, GameAction.confirm);
    expect(opened, isTrue);

    tester.view.physicalSize = const Size(1920, 720);
    await tester.pumpAndSettle();
    expect(tester.widgetList(shown).length, greaterThan(n), reason: 'a wider window shows more');
  });

  testWidgets('all fit: See all after them', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(shelf(3, onSeeAll: () {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('item-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('see-all')), findsOneWidget);
  });
}
