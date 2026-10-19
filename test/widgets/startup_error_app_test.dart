import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/sigil/sigil_library.dart';
import 'package:gargosy/ui/screens/startup_error_app.dart';

void main() {
  testWidgets('says what went wrong and what to do', (tester) async {
    await tester.pumpWidget(const StartupErrorApp(message: r'Access is denied: C:\Program Files\Gargosy\userdata'));
    expect(find.textContaining("Gargosy can't write to its folder"), findsOneWidget);
    expect(find.textContaining('Access is denied'), findsOneWidget);
    expect(find.textContaining('Move the Gargosy folder'), findsOneWidget);
  });

  testWidgets("a sigil.dll that won't load: says so, where it looked, and to unpack Gargosy again", (tester) async {
    final was = SigilLibrary.path;
    addTearDown(() => SigilLibrary.path = was);
    SigilLibrary.path = r'C:\nowhere\sigil.dll';
    final problem = SigilLibrary.problem();
    expect(problem, isNotNull);
    await tester.pumpWidget(StartupErrorApp.sigil(problem!));
    expect(find.text("Gargosy can't load sigil.dll"), findsOneWidget);
    expect(find.textContaining(r'C:\nowhere\sigil.dll'), findsOneWidget);
    expect(find.textContaining('Unpack the whole Gargosy zip again'), findsOneWidget);
  });
}
