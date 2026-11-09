import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/update/package_manager.dart';
import 'package:gargosy/update/update_installer.dart';
import 'package:gargosy/update/update_paths.dart';
import 'package:path/path.dart' as p;

import '../../helpers/profile_test_env.dart';

void main() {
  bool yes(String _) => true;
  bool no(String _) => false;

  group('PackageManager.of (#244)', () {
    test("Scoop's app folder, by version or current, with Scoop's manifest.json", () {
      expect(PackageManager.of(r'C:\Users\a\scoop\apps\gargosy\current', exists: yes), PackageManager.scoop);
      expect(PackageManager.of(r'D:\Scoop\Apps\Gargosy\0.10.0', exists: yes), PackageManager.scoop);
      expect(
        PackageManager.of(r'D:\apps\gargosy\Gargosy', exists: no),
        isNull,
        reason: r'unzipped by hand into apps\gargosy: no manifest.json',
      );
    });

    test("winget's package folder, with any source, user or machine", () {
      expect(
        PackageManager.of(
          r'C:\Users\a\AppData\Local\Microsoft\WinGet\Packages\GargIT.Gargosy_Microsoft.Winget.Source_8wekyb3d8bbwe\Gargosy',
        ),
        PackageManager.winget,
      );
      expect(
        PackageManager.of(r'C:\Program Files\WinGet\Packages\GargIT.Gargosy_Microsoft.Winget.Source_8wekyb3d8bbwe'),
        PackageManager.winget,
      );
    });

    test('a folder unzipped by hand is no package', () {
      expect(PackageManager.of(r'C:\Retro\apps\gargosy', exists: yes), isNull, reason: r'apps\gargosy itself');
      expect(PackageManager.of(r'D:\Games\Gargosy', exists: yes), isNull);
      expect(PackageManager.of(r'D:\scoop\apps\other\current', exists: yes), isNull);
      expect(PackageManager.of(r'D:\WinGet\Packages\Other.App_x\Gargosy'), isNull);
    });

    test("Scoop's version folder is worked from through current", () {
      const exe = r'C:\s\apps\gargosy\0.10.0\Gargosy.exe';
      expect(
        PackageManager.stableExecutable(exe, exists: yes, isDir: yes),
        p.join(r'C:\s\apps\gargosy', 'current', 'Gargosy.exe'),
      );
      expect(
        PackageManager.stableExecutable(exe, exists: no, isDir: yes),
        exe,
        reason: "not Scoop's",
      );
      expect(
        PackageManager.stableExecutable(exe, exists: yes, isDir: no),
        exe,
        reason: 'no current',
      );
      const current = r'C:\s\apps\gargosy\current\Gargosy.exe';
      expect(PackageManager.stableExecutable(current, exists: yes, isDir: yes), current);
      const other = r'D:\Games\Gargosy\Gargosy.exe';
      expect(PackageManager.stableExecutable(other, exists: yes, isDir: yes), other);
    });

    test('the winget warning is due once, and only for winget', () {
      final prefs = MemoryPrefs();
      expect(PackageManager.wingetWarningDue(PackageManager.scoop, prefs), isFalse);
      expect(PackageManager.wingetWarningDue(null, prefs), isFalse);
      expect(PackageManager.wingetWarningDue(PackageManager.winget, prefs), isTrue);
      prefs.values[PackageManager.wingetWarnedKey] = true;
      expect(PackageManager.wingetWarningDue(PackageManager.winget, prefs), isFalse);
    });
  });

  test("Gargosy's own Update hands over to the package manager", () async {
    final base = await io.Directory.systemTemp.createTemp('gargosy-pm');
    addTearDown(() => deleteTempDir(base.path));
    final root = AppRoot(p.join(base.path, 'scoop', 'apps', 'gargosy', 'current'));
    await root.ensureLayout();
    io.File(p.join(root.root, 'manifest.json')).writeAsStringSync('{}');
    // The updater is there: only the package manager stops it.
    io.File(UpdatePaths(root).installedUpdater).createSync(recursive: true);
    final installer = UpdateInstaller(
      root: root,
      pid: 1,
      args: const [],
      currentVersion: '0.10.0',
      platform: const PlatformInfo('windows'),
    );
    expect(installer.packageManager, PackageManager.scoop);
    expect(installer.canInstall, isFalse);
    expect(installer.whyNot, 'Installed with Scoop: update it with scoop update gargosy');
  });
}
