import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/ui/screens/startup_error_app.dart';

void main() {
  testWidgets('says what went wrong and what to do', (tester) async {
    await tester.pumpWidget(const StartupErrorApp(message: r'Access is denied: C:\Program Files\Gargosy\userdata'));
    expect(find.textContaining("Gargosy can't write to its folder"), findsOneWidget);
    expect(find.textContaining('Access is denied'), findsOneWidget);
    expect(find.textContaining('Move the Gargosy folder'), findsOneWidget);
  });
}
