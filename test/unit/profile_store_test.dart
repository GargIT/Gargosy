import 'dart:io' as io;
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/pin.dart';
import 'package:gargosy/profiles/profile.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_store.dart';
import 'package:path/path.dart' as p;

import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late MemoryPrefs prefs;
  late ProfileStore store;
  var ids = 0;

  setUp(() async {
    root = await tempAppRoot();
    prefs = MemoryPrefs();
    ids = 0;
    store = ProfileStore(root, prefs, newId: () => 'p${++ids}', now: () => DateTime(2026, 10, 8, 12, ids));
  });
  tearDown(() => io.Directory(root.root).delete(recursive: true));

  Future<Profile> anna() => store.create(
      name: 'Anna', colorIndex: 2, serverUrl: 'https://romm.example', rommUserId: 7, rommUsername: 'anna');

  test('create makes the folder layout and lists the profile', () async {
    final a = await anna();
    final paths = ProfilePaths(root, a.id);
    for (final d in [paths.dir, paths.emulatorsDir, paths.backups, paths.cache]) {
      expect(io.Directory(d).existsSync(), isTrue, reason: d);
    }
    final listed = await store.list();
    expect(listed.single.name, 'Anna');
    expect(listed.single.rommUserId, 7);
  });

  test('two profiles never share a path', () async {
    final a = await anna();
    final b = await store.create(name: 'Bob', colorIndex: 0, serverUrl: 'https://romm.example', rommUserId: 8, rommUsername: 'bob');
    final pa = ProfilePaths(root, a.id), pb = ProfilePaths(root, b.id);
    final aPaths = {pa.dir, pa.profileFile, pa.prefsFile, pa.avatarFile, pa.emulatorsDir, pa.emulatorDir('dolphin'), pa.backups, pa.cache};
    final bPaths = {pb.dir, pb.profileFile, pb.prefsFile, pb.avatarFile, pb.emulatorsDir, pb.emulatorDir('dolphin'), pb.backups, pb.cache};
    expect(aPaths.intersection(bPaths), isEmpty);
    expect(aPaths.any((x) => p.isWithin(pb.dir, x)), isFalse);
  });

  test('PathGuard of one profile rejects the other profile\'s folder', () async {
    final a = await anna();
    final b = await store.create(name: 'Bob', colorIndex: 0, serverUrl: 'https://romm.example', rommUserId: 8, rommUsername: 'bob');
    expect(() => ProfilePaths(root, a.id).guard.check(ProfilePaths(root, b.id).profileFile), throwsA(isA<PathGuardException>()));
  });

  test('create copies every emulator template into the new profile only', () async {
    final t = io.File(p.join(root.templates, 'dolphin', 'Config', 'Dolphin.ini'))..createSync(recursive: true);
    t.writeAsStringSync('[General]\n');
    final a = await anna();
    expect(io.File(p.join(ProfilePaths(root, a.id).emulatorDir('dolphin'), 'Config', 'Dolphin.ini')).readAsStringSync(), '[General]\n');
    expect(t.readAsStringSync(), '[General]\n');
  });

  test('the PIN is saved and checked; save keeps changes', () async {
    final a = await anna();
    await store.save(a.copyWith(name: 'Anna B', pin: PinHash.create('1234', random: Random(2), iterations: 1000)));
    final again = (await store.list()).single;
    expect(again.name, 'Anna B');
    expect(again.pin!.verify('1234'), isTrue);
    await store.save(again.copyWith(clearPin: true));
    expect((await store.list()).single.pin, isNull);
  });

  test('delete removes only that folder', () async {
    final a = await anna();
    final b = await store.create(name: 'Bob', colorIndex: 0, serverUrl: 'https://romm.example', rommUserId: 8, rommUsername: 'bob');
    await store.delete(a.id);
    expect(io.Directory(ProfilePaths(root, a.id).dir).existsSync(), isFalse);
    expect((await store.list()).map((x) => x.id), [b.id]);
  });

  test('a folder without profile.json, or with a damaged one, is skipped', () async {
    await anna();
    io.Directory(p.join(root.profiles, 'half')).createSync();
    io.File(p.join(root.profiles, 'bad', 'profile.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{oops');
    expect((await store.list()).map((x) => x.name), ['Anna']);
  });

  test('profiles are listed in creation order', () async {
    await anna();
    await store.create(name: 'Bob', colorIndex: 0, serverUrl: 's', rommUserId: 8, rommUsername: 'bob');
    expect((await store.list()).map((x) => x.name), ['Anna', 'Bob']);
  });

  test('last used profile is remembered in the app settings', () async {
    final a = await anna();
    expect(store.lastUsedId, isNull);
    await store.setLastUsed(a.id);
    expect(prefs.values[ProfileStore.lastProfileKey], a.id);
    expect(store.lastUsedId, a.id);
  });

  test('ids that would escape the profiles folder are refused', () {
    for (final bad in ['..', r'a\b', 'A B', '']) {
      expect(() => ProfilePaths(root, bad), throwsArgumentError, reason: bad);
    }
  });

  test('a create that fails partway removes the half-made folder', () async {
    // A file where the new profile's emulators folder should go makes create fail after the profile folder exists.
    io.File(p.join(root.profiles, 'p1', 'emulators'))
      ..createSync(recursive: true)
      ..writeAsStringSync('');
    await expectLater(anna(), throwsA(isA<io.FileSystemException>()));
    expect(io.Directory(p.join(root.profiles, 'p1')).existsSync(), isFalse);
  });
}
