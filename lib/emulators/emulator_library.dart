import '../core/emulator/pe_version_reader.dart';
import '../profiles/json_file.dart';

import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/emulator/emulator_strategy.dart';
import '../profiles/app_root.dart';
import '../profiles/path_guard.dart';
import '../profiles/profile_providers.dart';
import '../providers/engine_providers.dart';
import 'folder_link.dart';
import 'profile_launch_config.dart';
import '../l10n/tr.dart';

class EmulatorInfo {
  const EmulatorInfo({
    required this.id,
    required this.name,
    required this.exe,
    required this.supported,
    this.installedExe,
    this.installedFrom,
    this.version,
    this.downloadOff,
  });

  final String id;
  final String name;
  final String exe;

  /// Gargosy can start it on a profile's own data (docs/emulator-profiles.md).
  final bool supported;

  /// The exe under `emulators\<id>\`, when installed.
  final String? installedExe;

  /// The download it was installed from, or [EmulatorLibrary.imported].
  final String? installedFrom;

  /// The exe's own file version, when it records one.
  final String? version;

  /// Why Gargosy doesn't offer to download it right now; null when it does.
  /// Import from folder still works.
  final String? downloadOff;
}

/// The emulators Gargosy owns (spec §6), in `emulators\<id>\`.
class EmulatorLibrary {
  EmulatorLibrary(this.root, this.strategies);

  final AppRoot root;
  final List<EmulatorStrategy> strategies;

  /// Emulators whose download is off for now, and why.
  static const downloadsOff = <String, String>{
    // Ryubing's GitLab doesn't answer (2026-10-16); back on when it does (#9).
    'ryujinx': 'Download off: Ryubing\'s server can\'t be reached',
  };

  /// What an install keeps besides the program: left out on import.
  static const dataNames = <String, Set<String>>{
    'pcsx2': {
      'memcards',
      'sstates',
      'inis',
      'logs',
      'cache',
      'snaps',
      'covers',
      'videos',
      'textures',
      'gamesettings',
      'cheats',
      'patches',
      'bios',
      'portable.txt',
      'portable.ini',
    },
    'dolphin': {'user', 'portable.txt'},
    'ppsspp': {'memstick', 'installed.txt'},
    'duckstation': {
      'memcards',
      'savestates',
      'settings.ini',
      'portable.txt',
      'cache',
      'covers',
      'screenshots',
      'gamesettings',
      'inputprofiles',
      'shaders',
      'videos',
      'textures',
      'cheats',
      'patches',
      'subchannels',
      'gameicons',
      'bios',
    },
    'retroarch': {
      'saves',
      'states',
      'retroarch.cfg',
      'playlists',
      'logs',
      'screenshots',
      'config',
      'thumbnails',
      'downloads',
      'system',
    },
    'xenia_canary': {'content', 'cache', 'storage', 'xenia.log', 'xenia-canary.config.toml', 'portable.txt'},
    'ares': {'settings.bml'},
    'mgba': {'config.ini', 'qt.ini', 'portable.ini'},
    'flycast': {'emu.cfg', 'data'},
    'mame': {'cfg', 'nvram', 'sta', 'inp', 'snap', 'diff', 'comments', 'ini', 'mame.ini', 'ui.ini'},
    'xemu': {'xemu.toml'},
    // RPCS3's own data beside its exe: games, saves, firmware and caches.
    'rpcs3': {
      'config',
      'dev_hdd0',
      'dev_hdd1',
      'dev_flash',
      'dev_flash2',
      'dev_flash3',
      'dev_usb000',
      'dev_bdvd',
      'cache',
      'captures',
      'games',
      'log',
      'savestates',
      'shaderlog',
      'ppu_progs',
      'spu_progs',
      'patches',
      'portable',
      'rpcs3.buf',
    },
    // A portable ScummVM's own settings, saves and logs beside its exe.
    'scummvm': {'scummvm.ini', 'saves', 'screenshots', 'logs', 'scummvm.log', 'icons'},
    // A portable Ryujinx keeps its saves, keys and firmware in portable\;
    // Gargosy starts it with -r on the profile's folder instead.
    'ryujinx': {'portable'},
  };

  PathGuard get _guard => PathGuard(root);

  /// [EmulatorInfo.installedFrom] of an install copied from a folder.
  static const imported = 'import';

  static const _installFile = '.gargosy-install.json';

  /// Notes where the install in `emulators\<id>\` came from (a download's
  /// URL, or [imported]), so an update can tell whether it's the newest.
  Future<void> recordInstall(String id, {required String from}) => writeJsonObject(
    _guard,
    p.join(root.emulators, id, _installFile),
    {'from': from, 'at': DateTime.now().toUtc().toIso8601String()},
  );

  String? _installedFrom(String id) {
    try {
      return readJsonObjectSync(p.join(root.emulators, id, _installFile))?['from'] as String?;
    } on Object {
      return null;
    }
  }

  String? _findExe(String dir, String exe) {
    final d = io.Directory(dir);
    if (!d.existsSync()) return null;
    // Never through a folder link (issue #8): it leads into a profile's data.
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is io.File &&
          p.basename(e.path).toLowerCase() == exe.toLowerCase() &&
          p.split(p.relative(e.path, from: dir)).length <= 4) {
        return e.path;
      }
    }
    return null;
  }

  Future<List<EmulatorInfo>> list() async {
    final seen = <String>{};
    final out = <EmulatorInfo>[];
    for (final s in strategies) {
      if (s.emulatorId == 'windows_native' || s.windowsExecutable.isEmpty || !seen.add(s.emulatorId)) continue;
      final exe = _findExe(p.join(root.emulators, s.emulatorId), s.windowsExecutable);
      out.add(
        EmulatorInfo(
          id: s.emulatorId,
          name: s.name,
          exe: s.windowsExecutable,
          supported: ProfileLaunchConfig.supported.contains(s.emulatorId),
          installedExe: exe,
          installedFrom: exe == null ? null : _installedFrom(s.emulatorId),
          version: exe == null ? null : await PeVersionReader.fileVersion(exe),
          downloadOff: switch (downloadsOff[s.emulatorId]) {
            final why? => tr(why),
            null => null,
          },
        ),
      );
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Copies the program from an existing install in [folder] (never changing
  /// it), leaving its own user data and portable markers behind.
  Future<void> importFrom(String id, String folder) async {
    final strategy = strategies.firstWhere((s) => s.emulatorId == id);
    if (_findExe(folder, strategy.windowsExecutable) == null) {
      throw StateError(tr('{0} was not found in {1}', [strategy.windowsExecutable, folder]));
    }
    final target = _guard.check(p.join(root.emulators, id));
    final staging = _guard.check(p.join(root.emulators, '.$id.importing'));
    if (io.Directory(staging).existsSync()) io.Directory(staging).deleteSync(recursive: true);
    final skip = dataNames[id] ?? const <String>{};
    void copyDir(io.Directory from, String to) {
      io.Directory(to).createSync(recursive: true);
      // Never through a link (issue #8): another Gargosy's user\ link leads
      // into that profile's data, and a link back to a parent never ends.
      for (final e in from.listSync(followLinks: false)) {
        final name = p.basename(e.path);
        if (e is io.Link || skip.contains(name.toLowerCase())) continue;
        final dest = _guard.join(to, name);
        if (e is io.Directory) {
          copyDir(e, dest);
        } else if (e is io.File) {
          e.copySync(dest);
        }
      }
    }

    try {
      copyDir(io.Directory(folder), staging);
      removeFolderLinksIn(target);
      if (io.Directory(target).existsSync()) io.Directory(target).deleteSync(recursive: true);
      io.Directory(staging).renameSync(target);
      await recordInstall(id, from: imported);
    } finally {
      if (io.Directory(staging).existsSync()) io.Directory(staging).deleteSync(recursive: true);
    }
  }

  /// Before a download: a folder that holds no program (a download that
  /// failed, or the wrong file) is emptied, so nothing of it stays behind.
  /// An install with its program is left for the download to update.
  Future<void> clearIfNoProgram(String id) async {
    final exe = strategies.where((s) => s.emulatorId == id).firstOrNull?.windowsExecutable;
    if (exe == null || _findExe(p.join(root.emulators, id), exe) != null) return;
    await remove(id);
  }

  /// Removes the folder links in `emulators\<id>\` (issue #8); the number removed.
  int removeFolderLinks(String id) => removeFolderLinksIn(_guard.check(p.join(root.emulators, id)));

  /// Deletes `emulators\<id>\`, its folder links first (issue #8), so the
  /// delete can't reach a profile's data through one.
  Future<void> remove(String id) async {
    final dir = io.Directory(_guard.check(p.join(root.emulators, id)));
    removeFolderLinksIn(dir.path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

final emulatorLibraryProvider = Provider<EmulatorLibrary?>((ref) {
  final registry = ref.watch(strategyRegistryProvider);
  return registry == null ? null : EmulatorLibrary(ref.watch(appRootProvider), registry.allStrategies);
});

final emulatorsProvider = FutureProvider<List<EmulatorInfo>>((ref) async {
  final lib = ref.watch(emulatorLibraryProvider);
  return lib == null ? const [] : lib.list();
});
