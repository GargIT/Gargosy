import 'dart:convert';
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
import 'template_paths.dart';

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
    try {
      return await _create(paths, guard, name, colorIndex, serverUrl, rommUserId, rommUsername, pin, trustSelfSigned);
    } on Object {
      // No half-made profile stays behind.
      final dir = io.Directory(guard.check(paths.dir));
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } on io.FileSystemException catch (e) {
        debugPrint('[Profiles] Could not remove the half-made ${paths.id}: $e');
      }
      rethrow;
    }
  }

  Future<Profile> _create(
    ProfilePaths paths,
    PathGuard guard,
    String name,
    int colorIndex,
    String serverUrl,
    int rommUserId,
    String rommUsername,
    PinHash? pin,
    bool trustSelfSigned,
  ) async {
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
    await for (final entry in templates.list(recursive: true, followLinks: false)) {
      if (entry is! io.File) continue;
      final rel = p.relative(entry.path, from: root.templates);
      // A template being saved (`.<emu>.saving`) and a template's own note
      // (#301) aren't settings.
      if (p.split(rel).first.startsWith('.') || p.basename(rel) == templateManifest) continue;
      final target = io.File(guard.join(paths.emulatorsDir, rel));
      await target.parent.create(recursive: true);
      await entry.copy(target.path);
      // Only a template Gargosy made has markers; a folder an install had in
      // the way (NAND, saves) is copied as it is, never read whole.
      final emulator = p.split(rel).first;
      if (await io.File(p.join(root.templates, emulator, templateManifest)).exists() &&
          await entry.length() <= _markedMaxBytes) {
        await _fillProfilePaths(target, paths.dir);
      }
    }
  }

  /// Settings files are small; anything larger isn't read for markers.
  static const _markedMaxBytes = 4 * 1024 * 1024;

  /// A template's paths into the profile it was made from become this
  /// profile's (`template_paths.dart`), in the file's own encoding (UTF-8,
  /// else Latin-1, which gives every byte back).
  static Future<void> _fillProfilePaths(io.File file, String profileDir) async {
    final bytes = await file.readAsBytes();
    String text;
    Encoding encoding = utf8;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
      encoding = latin1;
    }
    if (hasTemplateMarker(text)) await file.writeAsBytes(encoding.encode(fromTemplateText(text, profileDir)));
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
