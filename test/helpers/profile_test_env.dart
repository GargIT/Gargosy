import 'dart:io' as io;

import 'package:gargosy/core/storage/app_preferences.dart';
import 'package:gargosy/profiles/app_root.dart';

/// [AppPreferences] in memory.
class MemoryPrefs implements AppPreferences {
  final values = <String, Object>{};
  @override
  String? getString(String key) => values[key] as String?;
  @override
  bool? getBool(String key) => values[key] as bool?;
  @override
  Set<String> getKeys() => values.keys.toSet();
  @override
  Future<bool> setString(String key, String value) async => (values[key] = value) == value;
  @override
  Future<bool> setBool(String key, bool value) async => (values[key] = value) == value;
  @override
  Future<bool> remove(String key) async => values.remove(key) != null;
}

/// Deletes a test's temp folder. Windows refuses while a file in it is still
/// open (a write the test started that is finishing), so it tries for a while.
Future<void> deleteTempDir(String path) async {
  for (var i = 0;; i++) {
    try {
      await io.Directory(path).delete(recursive: true);
      return;
    } on io.FileSystemException {
      if (i >= 50) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

/// A fresh Gargosy folder in the system temp dir, laid out.
Future<AppRoot> tempAppRoot() async {
  final dir = await io.Directory.systemTemp.createTemp('gargosy');
  final root = AppRoot(dir.path);
  await root.ensureLayout();
  return root;
}
