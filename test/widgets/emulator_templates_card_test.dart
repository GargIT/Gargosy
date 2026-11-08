import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/emulators/emulator_library.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_providers.dart';
import 'package:gargosy/ui/screens/settings/emulator_templates_card.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';
import '../helpers/widget_env.dart';

void main() {
  testWidgets("New profiles: this profile's settings become the template; Forget removes it", (tester) async {
    final root = (await tester.runAsync(tempAppRoot))!;
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    final paths = ProfilePaths(root, 'aaa');
    io.File(p.join(paths.emulatorDir('dolphin'), 'Config', 'GCPadNew.ini'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[GCPad1]\n');
    await setDesktopSize(tester);
    await tester.pumpWidget(
      testApp(
        const SingleChildScrollView(
          child: EmulatorTemplatesCard(
            installed: [
              EmulatorInfo(
                id: 'dolphin',
                name: 'Dolphin',
                exe: 'Dolphin.exe',
                supported: true,
                installedExe: r'C:\G\emulators\dolphin\Dolphin.exe',
              ),
              EmulatorInfo(
                id: 'pcsx2',
                name: 'PCSX2',
                exe: 'pcsx2-qt.exe',
                supported: true,
                installedExe: r'C:\G\emulators\pcsx2\pcsx2-qt.exe',
              ),
            ],
          ),
        ),
        root: root,
        overrides: [
          activeProfileProvider.overrideWith(
            (ref) => ActiveProfileNotifier(ref)
              ..state = ProfileContext(
                profile: Profile(
                  id: 'aaa',
                  name: 'Anna',
                  colorIndex: 0,
                  serverUrl: 'https://romm.example',
                  rommUserId: 1,
                  rommUsername: 'anna',
                  createdAt: DateTime(2026),
                ),
                paths: paths,
                guard: paths.guard,
                login: const ProfileLogin(token: 't', kind: 'device'),
              ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Its own settings'), findsNWidgets(2));
    expect(find.text('Forget'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('template-use-pcsx2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('This profile has no settings for PCSX2 yet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('template-use-dolphin')));
    await tester.pumpAndSettle();
    expect(find.textContaining("Anna's settings"), findsOneWidget);
    expect(io.File(p.join(root.templates, 'dolphin', 'Config', 'GCPadNew.ini')).existsSync(), isTrue);

    await tester.tap(find.byKey(const ValueKey('template-forget-dolphin')));
    await tester.pumpAndSettle();
    expect(find.text('Its own settings'), findsNWidgets(2));
    expect(io.Directory(p.join(root.templates, 'dolphin')).existsSync(), isFalse);
  });
}
