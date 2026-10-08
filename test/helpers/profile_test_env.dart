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

/// A fresh Gargosy folder in the system temp dir, laid out.
Future<AppRoot> tempAppRoot() async {
  final dir = await io.Directory.systemTemp.createTemp('gargosy');
  final root = AppRoot(dir.path);
  await root.ensureLayout();
  return root;
}
