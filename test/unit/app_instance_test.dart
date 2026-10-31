import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/app_instance.dart';
import 'package:gargosy/core/platform/instance_mutex.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/profiles/app_root.dart';

import '../helpers/profile_test_env.dart';

/// The named mutex is Windows' own.
final _notWindows = PlatformInfo.current.isWindows ? false : 'the named mutex is Windows only';

Future<AppInstance?> _claim(AppRoot root, List<String> args) =>
    AppInstance.claim(root, args, platform: PlatformInfo.current);

void main() {
  late AppRoot root;

  setUp(() async {
    root = await tempAppRoot();
  });
  tearDown(() => io.Directory(root.root).deleteSync(recursive: true));

  test('the claim stays referenced for the process, the mutex\'s and the lock file\'s alike', () async {
    for (final os in [if (PlatformInfo.current.isWindows) 'windows', 'linux']) {
      final claim = (await AppInstance.claim(root, const [], platform: PlatformInfo(os)))!;
      expect(claim.holds, isTrue, reason: os);
      expect(identical(AppInstance.held, claim), isTrue, reason: os);
      await claim.release();
      expect(AppInstance.held, isNull, reason: os);
    }
  });

  test('the first start holds the folder; a second hands its arguments over and is told to exit', () async {
    final first = (await _claim(root, const []))!;
    final got = first.requests.first;
    expect(await _claim(root, const ['--play=12', '--profile=aaa']), isNull);
    expect(await got, ['--play=12', '--profile=aaa']);
    await first.release();
  });

  test('once the first has gone, the next start holds the folder', () async {
    final first = (await _claim(root, const []))!;
    await first.release();
    final next = await _claim(root, const []);
    expect(next, isNotNull);
    await next!.release();
  });

  test('a message without the token is dropped', () async {
    final first = (await _claim(root, const []))!;
    final got = <List<String>>[];
    final sub = first.requests.listen(got.add);
    final s = await io.Socket.connect(io.InternetAddress.loopbackIPv4, _port(root));
    s.write('{"token":"wrong","args":["--play=1"]}\n');
    await s.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(got, isEmpty);
    await sub.cancel();
    await first.release();
  });

  test('what a later start sends before Gargosy listens waits for it', () async {
    final first = (await _claim(root, const []))!;
    expect(await _claim(root, const ['--play=3']), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await first.requests.first, ['--play=3']);
    await first.release();
  });

  test(
    'a folder held by a start that never answers: this start runs, holding nothing (Windows: the mutex)',
    () async {
      final holder = InstanceMutex.claim(root.root)!;
      io.File(AppInstance.infoPath(root)).writeAsStringSync('{"port": 1, "token": "x"}');
      final start = await AppInstance.claim(root, const ['--play=1'], platform: const PlatformInfo('windows'));
      expect(start, isNotNull);
      expect(start!.holds, isFalse);
      await start.release();
      holder.release();
    },
    timeout: const Timeout(Duration(seconds: 20)),
    skip: _notWindows,
  );

  test('elsewhere the lock file holds the folder', () async {
    final holder = await io.File(AppInstance.lockPath(root)).open(mode: io.FileMode.append);
    await holder.lock(io.FileLock.exclusive);
    io.File(AppInstance.infoPath(root)).writeAsStringSync('{"port": 1, "token": "x"}');
    final start = await AppInstance.claim(root, const ['--play=1'], platform: const PlatformInfo('linux'));
    expect(start!.holds, isFalse);
    await start.release();
    await holder.unlock();
    await holder.close();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('the mutex is per folder: another Gargosy folder starts on its own', () {
    final mine = InstanceMutex.claim(root.root)!;
    expect(InstanceMutex.claim(root.root), isNull);
    expect(InstanceMutex.claim(root.root.toUpperCase()), isNull, reason: 'the same folder, any case');
    final other = InstanceMutex.claim('${root.root}-other')!;
    other.release();
    mine.release();
    InstanceMutex.claim(root.root)!.release();
  }, skip: _notWindows);

  test('the mutex is the folder as Windows resolves it: a junction to it is the same folder', () {
    final link = io.Link('${root.root}-junction')..createSync(root.root);
    addTearDown(() => link.deleteSync());
    final mine = InstanceMutex.claim(root.root)!;
    expect(InstanceMutex.claim(link.path), isNull);
    mine.release();
  }, skip: _notWindows);

  test('the instance.json of a crashed holder is gone once the folder is claimed again', () async {
    io.File(AppInstance.infoPath(root)).writeAsStringSync('{"port": 1, "token": "old"}');
    final first = (await _claim(root, const []))!;
    expect(io.File(AppInstance.infoPath(root)).readAsStringSync(), isNot(contains('"old"')));
    await first.release();
  });
}

int _port(AppRoot root) {
  final text = io.File(AppInstance.infoPath(root)).readAsStringSync();
  return int.parse(RegExp(r'"port":\s*(\d+)').firstMatch(text)!.group(1)!);
}
