import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/storage/app_preferences.dart';
import 'json_file.dart';
import 'path_guard.dart';
import 'profile_paths.dart';

/// A profile's own settings (`profiles\<id>\prefs.json`): what Freegosy's
/// engine keeps in prefs (sync records, state records, per-game choices) is
/// per profile in Gargosy, so two profiles never share a sync state.
class ProfilePreferences implements AppPreferences {
  ProfilePreferences._(this._path, this._guard, this._values);

  static ProfilePreferences open(ProfilePaths paths) {
    Map<String, dynamic> raw;
    try {
      raw = readJsonObjectSync(paths.prefsFile) ?? const {};
    } on FormatException catch (e) {
      debugPrint('[Prefs] ${paths.prefsFile} is damaged ($e); starting empty');
      raw = const {};
    }
    return ProfilePreferences._(paths.prefsFile, paths.guard, {
      for (final e in raw.entries)
        if (e.value is String || e.value is bool) e.key: e.value as Object,
    });
  }

  final String _path;
  final PathGuard _guard;
  final Map<String, Object> _values;
  Future<void> _queue = Future.value();

  Future<bool> _persist() {
    final done = Completer<bool>();
    _queue = _queue.then((_) async {
      try {
        await writeJsonObject(_guard, _path, Map<String, dynamic>.of(_values));
        done.complete(true);
      } on Object catch (e) {
        debugPrint('[Prefs] could not save $_path: $e');
        done.complete(false);
      }
    });
    return done.future;
  }

  /// Waits for every pending write.
  Future<void> flush() => _queue;

  @override
  String? getString(String key) => _values[key] is String ? _values[key] as String : null;

  @override
  bool? getBool(String key) => _values[key] is bool ? _values[key] as bool : null;

  @override
  Set<String> getKeys() => _values.keys.toSet();

  @override
  Future<bool> setString(String key, String value) {
    _values[key] = value;
    return _persist();
  }

  @override
  Future<bool> setBool(String key, bool value) {
    _values[key] = value;
    return _persist();
  }

  @override
  Future<bool> remove(String key) {
    _values.remove(key);
    return _persist();
  }
}
