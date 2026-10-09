import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/emulators/emulator_installer.dart';
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

  testWidgets('Update says so when the newest is already installed', (tester) async {
    final installer = _FakeInstaller('https://example/dolphin-2.zip');
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const EmulatorsScreen(), overrides: [
      emulatorInstallerProvider.overrideWithValue(installer),
      emulatorsProvider.overrideWith((ref) async => const [
            EmulatorInfo(id: 'dolphin', name: 'Dolphin', exe: 'Dolphin.exe', supported: true,
                installedExe: r'C:\G\emulators\dolphin\Dolphin.exe', installedFrom: 'https://example/dolphin-2.zip', version: '2412'),
          ]),
    ]));
    await tester.pumpAndSettle();
    expect(find.textContaining('2412'), findsOneWidget);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already the newest'), findsOneWidget);
    expect(installer.installed, isEmpty);
  });

  testWidgets('Update installs a newer build', (tester) async {
    final installer = _FakeInstaller('https://example/dolphin-3.zip');
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const EmulatorsScreen(), overrides: [
      emulatorInstallerProvider.overrideWithValue(installer),
      emulatorsProvider.overrideWith((ref) async => const [
            EmulatorInfo(id: 'dolphin', name: 'Dolphin', exe: 'Dolphin.exe', supported: true,
                installedExe: r'C:\G\emulators\dolphin\Dolphin.exe', installedFrom: 'https://example/dolphin-2.zip'),
          ]),
    ]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(installer.installed, ['dolphin https://example/dolphin-3.zip']);
    expect(find.textContaining('Dolphin is installed'), findsOneWidget);
  });
}

class _FakeInstaller implements EmulatorInstaller {
  _FakeInstaller(this.latest);
  final String? latest;
  final installed = <String>[];

  @override
  Future<String?> latestUrl(String id) async => latest;

  @override
  Stream<InstallProgress> install(String id, String url) async* {
    installed.add('$id $url');
    yield const InstallProgress('done', 1);
  }
}
