import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

void main() {
  testWidgets('Gargosy starts on the profile picker', (tester) async {
    final h = AppHarness();
    await h.setUp(tester);
    await h.pumpApp(tester);
    expect(find.text('Who is playing?'), findsOneWidget);
  });
}
