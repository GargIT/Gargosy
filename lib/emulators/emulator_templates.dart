import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../profiles/app_root.dart';
import '../profiles/path_guard.dart';
import '../profiles/profile_paths.dart';
import '../profiles/profile_providers.dart';
import '../profiles/template_paths.dart';

/// Each emulator's settings in a profile's `emulators\<emu>\` folder (#301),
/// as paths relative to it (`/` between folders): what a template copies.
/// Only settings: never saves, states, memory cards, caches, logs or keys.
/// docs/emulator-profiles.md "Templates" lists the same.
const templateSettings = <String, List<String>>{
  'retroarch': ['retroarch.cfg', 'config'],
  'pcsx2': ['PCSX2/inis', 'PCSX2/inputprofiles', 'PCSX2/gamesettings'],
  'duckstation': ['settings.ini', 'gamesettings', 'inputprofiles'],
  'dolphin': ['Config', 'GameSettings'],
  'ppsspp': ['PSP/SYSTEM/ppsspp.ini', 'PSP/SYSTEM/controls.ini'],
  'mgba': ['config.ini', 'qt.ini'],
  'flycast': ['emu.cfg'],
  'mame': ['mame.ini', 'ui.ini', 'ini', 'cfg'],
  'ares': ['settings.bml'],
  'xenia_canary': ['storage/xenia-canary.config.toml'],
  'xemu': ['xemu.toml'],
  'scummvm': ['scummvm.ini'],
  'cemu': ['portable/settings.xml', 'portable/controllerProfiles'],
  'eden': ['user/config'],
  'azahar': ['user/config'],
  'melonds': ['portable/melonDS.toml'],
  'rpcs3': ['config/config.yml', 'config/input_configs', 'config/custom_configs'],
  'ryujinx': ['Config.json'],
};

/// Files that hold only a sign-in, left out wherever they are (any case):
/// PCSX2's RetroAchievements token, RPCS3's RPCN login, PPSSPP's
/// RetroAchievements token.
const templateLeftOut = {'secrets.ini', 'rpcn.yml', 'ppsspp_retroachievements.dat'};

/// A `key = value` (or `key: value`) line of an ini, cfg, TOML or YAML file.
final _keyLine = RegExp(r'^(\s*)([A-Za-z0-9_.\\/ -]+?)(\s*[=:]\s*)(.*?)(\r?)$', multiLine: true);

/// Whether [key] holds a sign-in: its last part (after `.`, `\` or `/`, as
/// QSettings and Flycast write sections into keys) ends in token, password or
/// username, or is a login time. The keys this catches, by emulator:
/// RetroArch `cheevos_token`, `cheevos_password`, `cheevos_username`,
/// `webdav_password`, `webdav_username`, `netplay_password`,
/// `netplay_spectate_password`; PCSX2 `[Achievements] Username`,
/// `LoginTimestamp`; DuckStation `[Cheevos] Username`, `Token`,
/// `LoginTimestamp`; Dolphin `RetroAchievements.ini` `Username`, `ApiToken`;
/// PPSSPP `AchievementsUserName`; Flycast's achievements `UserName`, `Token`;
/// Eden `yuzu_username`, `web_api_token`; Azahar `citra_username`,
/// `citra_token`.
bool isSignInKey(String key) {
  final last = key.trim().split(RegExp(r'[.\\/]')).last.toLowerCase();
  return last.endsWith('token') ||
      last.endsWith('password') ||
      last.endsWith('username') ||
      last.endsWith('user_name') ||
      last == 'logintimestamp';
}

/// [text] of a settings file with every sign-in emptied ([isSignInKey]);
/// RetroArch's achievements are also turned off, until the new profile's own
/// login turns them on at launch.
String withoutSignIns(String text, {bool toml = false}) {
  return text.replaceAllMapped(_keyLine, (m) {
    final key = m[2]!;
    final value = m[4]!;
    if (key.trim() == 'cheevos_enable') return '${m[1]}$key${m[3]}"false"${m[5]}';
    if (!isSignInKey(key) || value.isEmpty) return m[0]!;
    final quote = value.startsWith('"')
        ? '""'
        : value.startsWith("'")
        ? "''"
        : (toml ? '""' : '');
    return '${m[1]}$key${m[3]}$quote${m[5]}';
  });
}

/// A template Gargosy made: from which profile, and when.
class TemplateInfo {
  const TemplateInfo({required this.profileName, required this.savedAt});

  final String profileName;
  final DateTime savedAt;
}

/// The emulator settings new profiles start with (#301), in
/// `userdata\templates\<emu>\`: a copy of one profile's settings, sign-ins
/// left out, its paths into that profile kept as markers (`template_paths.dart`).
/// `ProfileStore.create` copies them into a new profile.
class EmulatorTemplates {
  EmulatorTemplates(this.root);

  final AppRoot root;

  String _dir(String id) => p.join(root.templates, id);

  /// The settings files of [id] in the profile's [data] folder (an emulator's
  /// `emulators\<id>\`), as paths relative to it. Never through a link.
  static List<String> settingsIn(String id, String data) {
    final out = <String>[];
    for (final rel in templateSettings[id] ?? const <String>[]) {
      final path = p.joinAll([data, ...rel.split('/')]);
      final type = io.FileSystemEntity.typeSync(path, followLinks: false);
      if (type == io.FileSystemEntityType.file) {
        if (!_leftOut(path)) out.add(p.relative(path, from: data));
      } else if (type == io.FileSystemEntityType.directory) {
        for (final e in io.Directory(path).listSync(recursive: true, followLinks: false)) {
          if (e is io.File && !_leftOut(e.path)) out.add(p.relative(e.path, from: data));
        }
      }
    }
    out.sort();
    return out;
  }

  static bool _leftOut(String path) => templateLeftOut.contains(p.basename(path).toLowerCase());

  /// The template of [id], when Gargosy made one. A folder another install
  /// left there (`folder_link.dart`'s first set-aside) isn't one.
  TemplateInfo? info(String id) {
    final note = io.File(p.join(_dir(id), templateManifest));
    if (!note.existsSync()) return null;
    try {
      final json = jsonDecode(note.readAsStringSync()) as Map<String, dynamic>;
      return TemplateInfo(
        profileName: json['profileName'] as String? ?? '',
        savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime(2000),
      );
    } on Object {
      return TemplateInfo(profileName: '', savedAt: DateTime(2000));
    }
  }

  /// Every emulator's template Gargosy made, by id.
  Map<String, TemplateInfo> all() => {for (final id in templateSettings.keys) id: ?info(id)};

  /// Makes [paths]' settings of [id] the template new profiles start with,
  /// replacing the one before. Returns how many files went in; none when the
  /// profile has no settings for it yet (nothing changes then). Something
  /// else in the template's place (not Gargosy's) goes to
  /// `userdata\app\set-aside\`, never deleted.
  int save(String id, ProfilePaths paths, {required String profileName, DateTime? now}) {
    final guard = paths.guard;
    final data = paths.emulatorDir(id);
    final files = settingsIn(id, data);
    if (files.isEmpty) return 0;
    final target = guard.check(_dir(id));
    final staging = guard.check(p.join(root.templates, '.$id.saving'));
    _delete(staging);
    try {
      for (final rel in files) {
        final from = io.File(p.join(data, rel));
        final to = io.File(guard.join(staging, rel));
        to.parent.createSync(recursive: true);
        final bytes = from.readAsBytesSync();
        final String text;
        try {
          text = utf8.decode(bytes);
        } on FormatException {
          to.writeAsBytesSync(bytes); // not text: no keys to read in it
          continue;
        }
        final clean = withoutSignIns(text, toml: rel.toLowerCase().endsWith('.toml'));
        to.writeAsStringSync(toTemplateText(clean, paths.dir));
      }
      io.File(guard.join(staging, templateManifest)).writeAsStringSync(
        jsonEncode({
          'emulator': id,
          'profile': paths.id,
          'profileName': profileName,
          'savedAt': (now ?? DateTime.now()).toIso8601String(),
        }),
      );
      if (io.Directory(target).existsSync()) {
        if (info(id) != null) {
          _delete(target);
        } else {
          final aside = guard.check(
            p.join(root.appData, 'set-aside', 'template-$id-${DateTime.now().millisecondsSinceEpoch}'),
          );
          io.Directory(p.dirname(aside)).createSync(recursive: true);
          io.Directory(target).renameSync(aside);
        }
      }
      io.Directory(staging).renameSync(target);
      return files.length;
    } finally {
      _delete(staging);
    }
  }

  /// Removes the template of [id] Gargosy made; new profiles start with the
  /// emulator's own settings again. Something Gargosy didn't make stays.
  bool forget(String id) {
    if (info(id) == null) return false;
    _delete(PathGuard(root).check(_dir(id)));
    return true;
  }

  static void _delete(String dir) {
    final d = io.Directory(dir);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}

final emulatorTemplatesProvider = Provider<EmulatorTemplates>((ref) => EmulatorTemplates(ref.watch(appRootProvider)));
