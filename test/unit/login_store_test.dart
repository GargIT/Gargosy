import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/pc_identity.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_secret_store.dart';
import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late ProfilePaths paths;
  late FakeSecretStore secrets;
  const pc = PcIdentity(machineName: 'LIVINGROOM', userName: 'henri', machineId: 'guid-1');

  setUp(() async {
    root = await tempAppRoot();
    paths = ProfilePaths(root, 'p1');
    secrets = FakeSecretStore();
  });
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  ProfileLoginStore store([PcIdentity id = pc]) => ProfileLoginStore(profileDir: paths.dir, secrets: secrets, pc: id);

  test('the file is named per PC and Windows user, inside the profile', () {
    expect(p.dirname(store().filePath), paths.dir);
    expect(p.basename(store().filePath), matches(RegExp(r'^login\.LIVINGROOM-henri-[0-9a-f]{8}\.dpapi$')));
    const other = PcIdentity(machineName: 'LAPTOP', userName: 'henri', machineId: 'guid-2');
    expect(store(other).filePath, isNot(store().filePath));
  });

  test('write then read gives the login back; the token is not in the file as text', () async {
    await store().write(paths.guard, const ProfileLogin(token: 'rmm_secret', kind: 'device', deviceId: 'd1'));
    final back = await store().read();
    expect(back!.token, 'rmm_secret');
    expect(back.kind, 'device');
    expect(back.deviceId, 'd1');
    expect(io.File(store().filePath).readAsStringSync(), isNot(contains('rmm_secret')));
  });

  test('no file, or a file another PC wrote, reads as no login', () async {
    expect(await store().read(), isNull);
    await store().write(paths.guard, const ProfileLogin(token: 't', kind: 'client-token'));
    secrets.fail = true;
    expect(await store().read(), isNull);
  });

  test('a damaged file reads as no login', () async {
    io.File(store().filePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    expect(await store().read(), isNull);
  });

  test('clear removes the file', () async {
    await store().write(paths.guard, const ProfileLogin(token: 't', kind: 'device'));
    await store().clear(paths.guard);
    expect(io.File(store().filePath).existsSync(), isFalse);
  });
}
