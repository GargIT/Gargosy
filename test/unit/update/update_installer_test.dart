import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/update/update_installer.dart';
import 'package:path/path.dart' as p;

import '../../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late List<(String, List<String>)> started;

  setUp(() async {
    root = await tempAppRoot();
    started = [];
  });
  tearDown(() => deleteTempDir(root.root));

  UpdateInstaller installer({List<String> args = const [], Map<String, String> env = const {}}) => UpdateInstaller(
        root: root,
        pid: 4242,
        args: args,
        currentVersion: '0.2.0-preview.4',
        platform: PlatformInfo('windows', environment: env),
        start: (exe, a) async => started.add((exe, a)),
      );

  void shipUpdater() => io.File(p.join(root.root, 'GargosyUpdate.exe')).writeAsStringSync('MZ updater');

  test('the command line: pid, root, the unpacked folder, versions, then Gargosy\'s own arguments', () {
    final cmd = installer(args: ['--root=D:\\My Games\\Gargosy', '--fullscreen', '--updated-from=0.1.0', '--update-failed'])
        .commandLine(r'D:\My Games\Gargosy\userdata\app\update\Gargosy', '0.2.0');
    expect(cmd, [
      '--pid', '4242',
      '--root', root.root,
      '--from', r'D:\My Games\Gargosy\userdata\app\update\Gargosy',
      '--version', '0.2.0',
      '--old-version', '0.2.0-preview.4',
      '--',
      '--root=D:\\My Games\\Gargosy', '--fullscreen', // the last update's markers are not passed on
    ]);
  });

  test('start copies the updater into userdata\\app\\update and starts that copy', () async {
    shipUpdater();
    final i = installer();
    io.Directory(i.paths.dir).createSync(recursive: true);
    io.File(i.paths.log).writeAsStringSync('old log');
    await i.start(i.paths.unpacked, '0.2.0');
    expect(started.single.$1, p.join(root.appData, 'update', 'GargosyUpdate.exe'));
    expect(io.File(started.single.$1).readAsStringSync(), 'MZ updater');
    expect(started.single.$2, containsAllInOrder(['--pid', '4242', '--from', i.paths.unpacked]));
    expect(io.File(i.paths.log).existsSync(), isFalse, reason: "the last update's log isn't read as this one's");
  });

  test('refused without GargosyUpdate.exe beside Gargosy.exe', () async {
    final i = installer();
    expect(i.canInstall, isFalse);
    expect(i.whyNot, contains('by hand'));
    await expectLater(i.start(i.paths.unpacked, '0.2.0'), throwsStateError);
    expect(started, isEmpty);
  });

  test('hidden in a folder Windows protects (Program Files)', () {
    shipUpdater();
    expect(installer(env: {'ProgramFiles': p.dirname(root.root)}).canInstall, isFalse);
    expect(installer(env: {'ProgramFiles': p.join(p.dirname(root.root), 'elsewhere')}).canInstall, isTrue);
  });

  test('after --updated-from: previous files, zip, unpacked folder and updater copy are deleted', () async {
    final i = installer();
    io.Directory(p.join(i.paths.previous, 'data')).createSync(recursive: true);
    io.Directory(i.paths.unpacked).createSync(recursive: true);
    io.File(i.paths.zip('0.2.0')).writeAsStringSync('zip');
    io.File(i.paths.updaterCopy).writeAsStringSync('MZ');
    io.File(i.paths.log).writeAsStringSync('done\n');
    final outcome = await i.afterStart(['--updated-from=0.1.0']);
    expect((outcome! as UpdatedFrom).oldVersion, '0.1.0');
    await i.cleaning;
    expect(io.Directory(i.paths.dir).listSync().map((e) => p.basename(e.path)), ['update.log']);
  });

  test('after --update-failed: the last line of update.log, and nothing is deleted', () async {
    final i = installer();
    io.Directory(i.paths.unpacked).createSync(recursive: true);
    io.File(i.paths.log).writeAsStringSync('Waiting for Gargosy\nCopying data\\app.so\nFailed: data\\app.so is locked. The old version is back.\n\n');
    final outcome = await i.afterStart(['--update-failed']);
    expect((outcome! as UpdateFailed).detail, r'Failed: data\app.so is locked. The old version is back.');
    expect(io.Directory(i.paths.unpacked).existsSync(), isTrue);
  });

  test("the updater's line is shown without its time", () async {
    final i = installer();
    io.Directory(i.paths.dir).createSync(recursive: true);
    io.File(i.paths.log).writeAsStringSync(
        '2026-10-14 12:03:07  Waiting for Gargosy\r\n2026-10-14 12:03:09  Failed: data\\app.so is locked. The old version is back.\r\n');
    final outcome = await i.afterStart(['--update-failed']);
    expect((outcome! as UpdateFailed).detail, r'Failed: data\app.so is locked. The old version is back.');
  });

  test('a normal start reports nothing', () async {
    expect(await installer().afterStart(['--fullscreen']), isNull);
    expect(await installer().afterStart(['--update-failed']), isA<UpdateFailed>().having((f) => f.detail, 'detail', isNull));
  });
}
