import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/widgets/error_retry.dart';

import '../helpers/widget_env.dart';

void main() {
  testWidgets('a long error fits a small box, and Retry is still there', (tester) async {
    await tester.pumpWidget(
      testApp(
        SizedBox(
          height: 200,
          width: 600,
          child: ErrorRetry(message: 'DioException [bad response]: ${'x' * 800}', onRetry: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Retry'), findsOneWidget);
  });
}
