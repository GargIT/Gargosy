import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/avatar_refresh.dart';
import 'package:gargosy/profiles/login_store.dart';
import 'package:gargosy/profiles/profile.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_store.dart';

import '../helpers/fake_romm_auth.dart';
import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late ProfileStore store;
  late Profile anna;
  late ProfilePaths paths;
  const login = ProfileLogin(token: 't', kind: 'device');
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);

  setUp(() async {
    root = await tempAppRoot();
    store = ProfileStore(root, MemoryPrefs());
    anna = await store.create(name: 'Anna', colorIndex: 0, serverUrl: 'https://r', rommUserId: 7, rommUsername: 'anna');
    paths = ProfilePaths(root, anna.id);
  });
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  Future<Profile?> refresh(Profile p, Uint8List? avatar) => refreshAvatar(
    profile: p,
    login: login,
    auth: FakeRommAuth(avatar: avatar),
    store: store,
    paths: paths,
  );

  test('an avatar added in RomM after the profile was made is picked up', () async {
    final updated = await refresh(anna, png);
    expect(updated!.hasAvatar, isTrue);
    expect(io.File(paths.avatarFile).readAsBytesSync(), png);
    expect((await store.list()).single.hasAvatar, isTrue);
  });

  test('the same avatar again changes nothing', () async {
    final first = (await refresh(anna, png))!;
    final written = io.File(paths.avatarFile).lastModifiedSync();
    expect(await refresh(first, png), isNull);
    expect(io.File(paths.avatarFile).lastModifiedSync(), written);
  });

  test('a changed avatar replaces the old one', () async {
    final first = (await refresh(anna, png))!;
    final newer = Uint8List.fromList([...png, 9, 9]);
    expect(await refresh(first, newer), isNotNull);
    expect(io.File(paths.avatarFile).readAsBytesSync(), newer);
  });

  test('no avatar on RomM, or an answer that is not an image, leaves the profile as it is', () async {
    expect(await refresh(anna, null), isNull);
    expect(await refresh(anna, Uint8List.fromList('<!doctype html>'.codeUnits)), isNull);
    expect(io.File(paths.avatarFile).existsSync(), isFalse);
    expect((await store.list()).single.hasAvatar, isFalse);
  });
}
