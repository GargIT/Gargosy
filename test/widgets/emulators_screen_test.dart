import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/emulators/emulator_library.dart';
import 'package:gargosy/ui/screens/emulators_screen.dart';

import '../helpers/widget_env.dart';

void main() {
  testWidgets('lists emulators with their state; unsupported ones say so', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const EmulatorsScreen(), overrides: [
      emulatorsProvider.overrideWith((ref) async => const [
            EmulatorInfo(id: 'dolphin', name: 'Dolphin', exe: 'Dolphin.exe', supported: true, installedExe: r'C:\G\emulators\dolphin\Dolphin.exe'),
            EmulatorInfo(id: 'pcsx2', name: 'PCSX2', exe: 'pcsx2-qt.exe', supported: true),
            EmulatorInfo(id: 'ryujinx', name: 'Ryujinx', exe: 'Ryujinx.exe', supported: false),
          ]),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Dolphin'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Import from folder'), findsWidgets);
    expect(find.text('Not supported yet'), findsOneWidget);
  });
}
