import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/profiles/profile_preferences.dart';

import '../helpers/profile_test_env.dart';

void main() {
  test('values persist in the profile\'s prefs.json and nowhere else', () async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).delete(recursive: true));
    final a = ProfilePaths(root, 'aaa');
    final b = ProfilePaths(root, 'bbb');
    final pa = ProfilePreferences.open(a);
    await pa.setString('save_sync_record_1', 'x');
    await pa.setBool('flag', true);
    await pa.flush();
    expect(io.File(a.prefsFile).existsSync(), isTrue);
    final again = ProfilePreferences.open(a);
    expect(again.getString('save_sync_record_1'), 'x');
    expect(again.getBool('flag'), isTrue);
    expect(ProfilePreferences.open(b).getKeys(), isEmpty);
    await again.remove('flag');
    await again.flush();
    expect(ProfilePreferences.open(a).getBool('flag'), isNull);
  });

  test('a damaged prefs.json starts empty instead of failing', () async {
    final root = await tempAppRoot();
    addTearDown(() => io.Directory(root.root).delete(recursive: true));
    final a = ProfilePaths(root, 'aaa');
    io.File(a.prefsFile)..createSync(recursive: true)..writeAsStringSync('{oops');
    expect(ProfilePreferences.open(a).getKeys(), isEmpty);
  });
}
