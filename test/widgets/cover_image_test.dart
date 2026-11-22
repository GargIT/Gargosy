import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/widgets/cover_image.dart';

import '../helpers/widget_env.dart';

void main() {
  testWidgets('a game without a cover shows the placeholder art and its title', (tester) async {
    await tester.pumpWidget(testApp(const CoverImage(title: 'Tetris', width: 140, height: 188)));
    expect(find.byType(CoverArt), findsOneWidget);
    expect(find.text('Tetris'), findsOneWidget);
  });

  testWidgets('a cover is drawn without the placeholder art under it (#315)', (tester) async {
    await tester.pumpWidget(testApp(const CoverImage(url: 'https://romm/c.png', title: 'Tetris', width: 140)));
    expect(find.byKey(const ValueKey('cover:https://romm/c.png')), findsOneWidget);
    expect(find.byType(CoverArt), findsNothing);
    expect(find.text('Tetris'), findsNothing);
  });

  testWidgets('the placeholder art paints at any size', (tester) async {
    for (final size in const [Size(66, 88), Size(140, 188), Size(1, 1), Size.zero]) {
      await tester.pumpWidget(
        testApp(
          Center(
            child: SizedBox.fromSize(size: size, child: const CoverArt()),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
