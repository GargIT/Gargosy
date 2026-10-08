import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/storage/app_preferences.dart';
import 'app_root.dart';
import 'json_file.dart';
import 'path_guard.dart';
import 'pin.dart';
import 'profile.dart';
import 'profile_paths.dart';

/// The profiles in `userdata\profiles\`. A profile exists once its
/// `profile.json` is written, which is the last step of [create].
class ProfileStore {
  ProfileStore(this.root, this.prefs, {String Function()? newId, DateTime Function()? now})
      : _newId = newId ?? (() => const Uuid().v4()),
        _now = now ?? DateTime.now;

  final AppRoot root;
  final AppPreferences prefs;
  final String Function() _newId;
  final DateTime Function() _now;

  static const lastProfileKey = 'last_profile_id';

  /// Reads synchronously on purpose: a handful of tiny files, and the picker
  /// (and widget tests, whose fake clock never completes async file reads)
  /// gets them in one go.
  Future<List<Profile>> list() async {
    final dir = io.Directory(root.profiles);
    if (!dir.existsSync()) return [];
    final profiles = <Profile>[];
    for (final entry in dir.listSync()) {
      if (entry is! io.Directory) continue;
      try {
        final json = readJsonObjectSync(p.join(entry.path, 'profile.json'));
        if (json != null) profiles.add(Profile.fromJson(json));
      } on Object catch (e) {
        debugPrint('[Profiles] Skipping ${p.basename(entry.path)}: $e');
      }
    }
    profiles.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return profiles;
  }

  Future<Profile> create({
    required String name,
    required int colorIndex,
    required String serverUrl,
    required int rommUserId,
    required String rommUsername,
    PinHash? pin,
    bool trustSelfSigned = false,
  }) async {
    final paths = ProfilePaths(root, _newId());
    final guard = paths.guard;
    for (final d in [paths.dir, paths.emulatorsDir, paths.backups, paths.cache]) {
      await io.Directory(guard.check(d)).create(recursive: true);
    }
    await _copyTemplates(guard, paths);
    final profile = Profile(
      id: paths.id,
      name: name,
      colorIndex: colorIndex,
      serverUrl: serverUrl,
      rommUserId: rommUserId,
      rommUsername: rommUsername,
      createdAt: _now(),
      pin: pin,
      trustSelfSigned: trustSelfSigned,
    );
    await writeJsonObject(guard, paths.profileFile, profile.toJson());
    return profile;
  }

  Future<void> _copyTemplates(PathGuard guard, ProfilePaths paths) async {
    final templates = io.Directory(root.templates);
    if (!await templates.exists()) return;
    await for (final entry in templates.list(recursive: true)) {
      if (entry is! io.File) continue;
      final rel = p.relative(entry.path, from: root.templates);
      final target = io.File(guard.join(paths.emulatorsDir, rel));
      await target.parent.create(recursive: true);
      await entry.copy(target.path);
    }
  }

  Future<void> save(Profile profile) {
    final paths = ProfilePaths(root, profile.id);
    return writeJsonObject(paths.guard, paths.profileFile, profile.toJson());
  }

  /// Removes the profile's folder. Nothing on RomM is touched.
  Future<void> delete(String id) async {
    final paths = ProfilePaths(root, id);
    final dir = io.Directory(paths.guard.check(paths.dir));
    if (await dir.exists()) await dir.delete(recursive: true);
    if (lastUsedId == id) await prefs.remove(lastProfileKey);
  }

  String? get lastUsedId => prefs.getString(lastProfileKey);

  Future<void> setLastUsed(String id) => prefs.setString(lastProfileKey, id);
}
