import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/app_instance.dart';
import 'package:gargosy/core/platform/instance_mutex.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/profiles/app_root.dart';

import '../helpers/profile_test_env.dart';

void main() {
  test('the claim stays referenced for the process, so its lock file is never collected and closed', () async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).deleteSync(recursive: true));
    final claim = (await AppInstance.claim(root, const []))!;
    expect(claim.holds, isTrue);
    expect(identical(AppInstance.held, claim), isTrue);
    await claim.release();
    expect(AppInstance.held, isNull);
  });

  late AppRoot root;

  setUp(() async {
    root = await tempAppRoot();
  });
  tearDown(() => io.Directory(root.root).deleteSync(recursive: true));

  test('the first start holds the folder; a second hands its arguments over and is told to exit', () async {
    final first = (await AppInstance.claim(root, const []))!;
    final got = first.requests.first;
    expect(await AppInstance.claim(root, const ['--play=12', '--profile=aaa']), isNull);
    expect(await got, ['--play=12', '--profile=aaa']);
    await first.release();
  });

  test('once the first has gone, the next start holds the folder', () async {
    final first = (await AppInstance.claim(root, const []))!;
    await first.release();
    final next = await AppInstance.claim(root, const []);
    expect(next, isNotNull);
    await next!.release();
  });

  test('a message without the token is dropped', () async {
    final first = (await AppInstance.claim(root, const []))!;
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
    final first = (await AppInstance.claim(root, const []))!;
    expect(await AppInstance.claim(root, const ['--play=3']), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await first.requests.first, ['--play=3']);
    await first.release();
  });

  test('a folder held by a start that never answers: this start runs, holding nothing (Windows: the mutex)', () async {
    final holder = InstanceMutex.claim(root.root)!;
    io.File(AppInstance.infoPath(root)).writeAsStringSync('{"port": 1, "token": "x"}');
    final start = await AppInstance.claim(root, const ['--play=1'], platform: const PlatformInfo('windows'));
    expect(start, isNotNull);
    expect(start!.holds, isFalse);
    await start.release();
    holder.release();
  }, timeout: const Timeout(Duration(seconds: 20)));

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

  test('the mutex is per folder: another Gargosy folder starts on its own', () async {
    final mine = InstanceMutex.claim(root.root)!;
    expect(InstanceMutex.claim(root.root), isNull, reason: 'the same folder, any case');
    expect(InstanceMutex.claim(root.root.toUpperCase()), isNull);
    final other = InstanceMutex.claim('${root.root}-other')!;
    other.release();
    mine.release();
    InstanceMutex.claim(root.root)!.release();
  });

  test('the instance.json of a crashed holder is gone once the folder is claimed again', () async {
    io.File(AppInstance.infoPath(root)).writeAsStringSync('{"port": 1, "token": "old"}');
    final first = (await AppInstance.claim(root, const []))!;
    expect(io.File(AppInstance.infoPath(root)).readAsStringSync(), isNot(contains('"old"')));
    await first.release();
  });
}

int _port(AppRoot root) {
  final text = io.File(AppInstance.infoPath(root)).readAsStringSync();
  return int.parse(RegExp(r'"port":\s*(\d+)').firstMatch(text)!.group(1)!);
}
