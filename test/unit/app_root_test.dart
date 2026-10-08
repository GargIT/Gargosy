import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:path/path.dart' as p;

void main() {
  late io.Directory tmp;
  setUp(() async => tmp = await io.Directory.systemTemp.createTemp('approot'));
  tearDown(() => tmp.delete(recursive: true));

  test('the root is the folder of Gargosy.exe', () {
    final root = AppRoot.fromArgs([], r'D:\Games\Gargosy\Gargosy.exe');
    expect(root.root, r'D:\Games\Gargosy');
    expect(root.roms, r'D:\Games\Gargosy\roms');
    expect(root.emulators, r'D:\Games\Gargosy\emulators');
    expect(root.bios, r'D:\Games\Gargosy\bios');
    expect(root.settingsFile, r'D:\Games\Gargosy\userdata\settings.json');
    expect(root.templates, r'D:\Games\Gargosy\userdata\templates');
    expect(root.profiles, r'D:\Games\Gargosy\userdata\profiles');
    expect(root.appData, r'D:\Games\Gargosy\userdata\app');
  });

  test('--root=<dir> overrides the exe folder (for flutter run)', () {
    final root = AppRoot.fromArgs(['--root=E:\\Dev\\G'], r'D:\x\Gargosy.exe');
    expect(root.root, r'E:\Dev\G');
  });

  test('ensureLayout creates every folder and leaves no probe file', () async {
    final root = AppRoot(tmp.path);
    await root.ensureLayout();
    for (final d in [root.roms, root.emulators, root.bios, root.templates, root.profiles, root.appData]) {
      expect(io.Directory(d).existsSync(), isTrue, reason: d);
    }
    expect(io.File(p.join(root.userdata, '.write-test')).existsSync(), isFalse);
  });

  test('ensureLayout throws on a read-only root', () async {
    // A file where userdata should be makes the layout impossible to create.
    await io.File(p.join(tmp.path, 'userdata')).writeAsString('');
    expect(() => AppRoot(tmp.path).ensureLayout(), throwsA(isA<io.FileSystemException>()));
  });
}
