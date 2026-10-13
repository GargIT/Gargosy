import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/storage/ini_file.dart';
import '../profiles/app_root.dart';
import 'profile_launch_config.dart';

/// RPCS3 (PS3) on a profile's data (issue #10): started with
/// `RPCS3_CONFIG_DIR=<data>\`, so `config.yml`, `vfs.yml` and `dev_hdd0`
/// (saves, licences, installed updates and DLC) are the profile's. The
/// installed firmware (`dev_flash`, ~200 MB) is shared: the profile's
/// `config\vfs.yml` points `/dev_flash/` at `emulators\rpcs3-firmware\dev_flash\`, so it's
/// installed once. `dev_flash2`/`dev_flash3` stay per profile.
class Rpcs3Config extends ProfileLaunchConfig {
  const Rpcs3Config();

  /// The firmware every profile reads: beside RPCS3's install, not in it,
  /// so removing, updating or importing RPCS3 never deletes it.
  static String sharedFlash(LaunchContext c) => sharedFlashIn(c.guard.root);

  static String sharedFlashIn(AppRoot root) => p.join(root.emulators, 'rpcs3-firmware', 'dev_flash');

  @override
  Future<List<String>> prepare(LaunchContext c) async {
    io.Directory(c.guard.check(c.data)).createSync(recursive: true);
    // A portable\ beside the exe wins over RPCS3_CONFIG_DIR (File.cpp):
    // turned off, never deleted.
    final portable = io.Directory(p.join(c.exeDir, 'portable'));
    if (portable.existsSync()) {
      var off = '${portable.path}.gargosy-off';
      for (var n = 2; io.FileSystemEntity.typeSync(off) != io.FileSystemEntityType.notFound; n++) {
        off = '${portable.path}.gargosy-off-$n';
      }
      portable.renameSync(c.guard.check(off));
    }
    _writeVfs(c);
    _hideStartDialogs(c);
    return const [];
  }

  @override
  Map<String, String> environment(LaunchContext c) => {'RPCS3_CONFIG_DIR': '${c.data}${p.separator}'};

  /// The Gargosy folder moved: the shared firmware's path in vfs.yml follows.
  @override
  void repoint(LaunchContext c) {
    if (io.File(vfsPath(c)).existsSync()) _writeVfs(c);
  }

  /// Where RPCS3 reads vfs.yml with RPCS3_CONFIG_DIR set: its config\
  /// subfolder, beside config.yml (probed: a vfs.yml at the top is ignored).
  static String vfsPath(LaunchContext c) => p.join(c.data, 'config', 'vfs.yml');

  /// RPCS3's Welcome box and the box after a firmware install want a mouse
  /// click: off in the profile's GUI settings (probed on 0.0.43).
  void _hideStartDialogs(LaunchContext c) {
    final ini = io.File(c.guard.check(p.join(c.data, 'GuiConfigs', 'CurrentSettings.ini')));
    final text = ini.existsSync() ? ini.readAsStringSync() : '';
    final out = IniFile(text)
      ..set('main_window', 'infoBoxEnabledWelcome', 'false')
      ..set('main_window', 'infoBoxEnabledInstallPUP', 'false');
    ini.parent.createSync(recursive: true);
    ini.writeAsStringSync(out.toText());
  }

  void _writeVfs(LaunchContext c) {
    final vfs = io.File(c.guard.check(vfsPath(c)));
    vfs.parent.createSync(recursive: true);
    final flash = io.Directory(c.guard.check(sharedFlash(c)));
    flash.createSync(recursive: true);
    final text = vfs.existsSync() ? vfs.readAsStringSync() : '';
    // Quoted: a folder name with '#' or ': ' would otherwise end the value.
    final path = '${flash.path.replaceAll(r'\', '/')}/'.replaceAll("'", "''");
    vfs.writeAsStringSync(setYamlKeys(text, {'/dev_flash/': "'$path'"}));
  }
}

/// [text] (a flat YAML file, RPCS3's vfs.yml) with each top-level `key: value`
/// in [values] set, replacing the key's line or adding it; other lines kept.
String setYamlKeys(String text, Map<String, String> values) {
  final lines = text.isEmpty ? <String>[] : text.split(RegExp(r'\r?\n'));
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  for (final e in values.entries) {
    final line = '${e.key}: ${e.value}';
    final i = lines.indexWhere((l) => l.startsWith('${e.key}:'));
    if (i >= 0) {
      lines[i] = line;
    } else {
      lines.add(line);
    }
  }
  return '${lines.join('\n')}\n';
}
