import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/app_instance.dart';
import 'package:gargosy/profiles/app_root.dart';

import '../helpers/profile_test_env.dart';

void main() {
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

  test('a folder held by a start that never answers: the hand-over gives up', () async {
    expect(await AppInstance.handOver(root, const ['--play=1'], tries: 2), isFalse);
  });
}

int _port(AppRoot root) {
  final text = io.File(AppInstance.infoPath(root)).readAsStringSync();
  return int.parse(RegExp(r'"port":\s*(\d+)').firstMatch(text)!.group(1)!);
}
