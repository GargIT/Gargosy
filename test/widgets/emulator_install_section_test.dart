import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/emulators/bios_sync.dart';
import 'package:gargosy/emulators/emulator_installer.dart';
import 'package:gargosy/emulators/emulator_library.dart';
import 'package:gargosy/ui/screens/settings/emulator_install_section.dart';

import '../helpers/widget_env.dart';

void main() {
  testWidgets('lists emulators with their state; unsupported ones say so', (tester) async {
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const EmulatorInstallSection(), overrides: [
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
    await tester.pumpWidget(testApp(const EmulatorInstallSection(), overrides: [
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

  testWidgets('Update installs a newer build, then fetches its BIOS files from RomM', (tester) async {
    final installer = _FakeInstaller('https://example/dolphin-3.zip');
    final biosFor = <String>[];
    await setDesktopSize(tester);
    await tester.pumpWidget(testApp(const EmulatorInstallSection(), overrides: [
      emulatorInstallerProvider.overrideWithValue(installer),
      biosSyncProvider.overrideWithValue(_Bios(biosFor)),
      emulatorsProvider.overrideWith((ref) async => const [
            EmulatorInfo(id: 'dolphin', name: 'Dolphin', exe: 'Dolphin.exe', supported: true,
                installedExe: r'C:\G\emulators\dolphin\Dolphin.exe', installedFrom: 'https://example/dolphin-2.zip'),
          ]),
    ]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(installer.installed, ['dolphin https://example/dolphin-3.zip']);
    expect(biosFor, ['dolphin']);
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

class _Bios implements BiosSync {
  _Bios(this.calls);
  final List<String> calls;

  @override
  Future<int> forEmulator(String emulatorId) async {
    calls.add(emulatorId);
    return 0;
  }

  @override
  Future<int> forAll(Set<String> installed) async => 0;
}
