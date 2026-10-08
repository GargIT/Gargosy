import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/app.dart';

void main() {
  testWidgets('the app starts and shows its name', (tester) async {
    await tester.pumpWidget(const GargosyApp());
    expect(find.text('Gargosy'), findsOneWidget);
  });
}
