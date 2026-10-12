import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/storage/ini_file.dart';
import 'bios_links.dart';
import 'config_files.dart';
import 'linked_folder_config.dart';
import 'profile_launch_config.dart';

/// The emulators that only read a folder next to their exe, pointed at the
/// profile by a folder link (issue #8), and what each one's settings step
/// does after the link is in place (issues #12–#15). Key names come from
/// the emulators' sources (`docs/emulator-profiles.md`); each still needs
/// its probe on Windows.
final linkedEmulatorConfigs = <String, ProfileLaunchConfig>{
  // Eden (Switch, #12): `user\` beside the exe, else %APPDATA%\eden.
  'eden': const LinkedFolderConfig('user', then: _Step(_eden)),
  // Azahar (3DS, #13): `user\` beside the exe, else %APPDATA%\Azahar.
  'azahar': const LinkedFolderConfig('user', then: _Step(_azahar)),
  // Cemu (Wii U, #14): `portable\` beside the exe; the MLC (the saves) is
  // the profile's own, given with -m.
  'cemu': LinkedFolderConfig('portable', then: _Step(_cemu, args: (c) => ['-m', cemuMlc(c)])),
  // melonDS (DS, #15): `portable\` beside the exe; saves and states set in
  // its melonDS.toml, never next to the ROM.
  'melonds': const LinkedFolderConfig('portable', then: _Step(_melonDs)),
};

/// A settings step: [before] edits the profile's files, [args] are the
/// arguments it adds.
class _Step extends ProfileLaunchConfig {
  const _Step(this.before, {this.args});
  final void Function(LaunchContext c) before;
  final List<String> Function(LaunchContext c)? args;

  @override
  Future<List<String>> prepare(LaunchContext c) async {
    before(c);
    return args?.call(c) ?? const [];
  }

  @override
  void repoint(LaunchContext c) => before(c);
}

/// The shared BIOS files named [names] placed in [folder] (hard links).
void _keysInto(LaunchContext c, String folder, List<List<String>> names) {
  for (final alternatives in names) {
    final file = findBiosFile(c.bios, alternatives);
    if (file != null) placeSharedFile(file, p.join(folder, p.basename(file.path)), c.guard);
  }
}

/// The roms\<platform> folders in a Qt `qt-config.ini`'s game list, once
/// the emulator has made its own list.
void _qtGameDirs(LaunchContext c, String iniPath) {
  final file = io.File(iniPath);
  if (!file.existsSync() || c.gameFolders.isEmpty) return;
  final ini = IniFile(file.readAsStringSync());
  if (addQtArrayPaths(ini, 'UI', r'Paths\gamedirs', c.gameFolders)) {
    io.File(c.guard.check(iniPath)).writeAsStringSync(ini.toText());
  }
}

void _eden(LaunchContext c) {
  final user = p.join(c.data, 'user');
  // Keys from RomM's firmware (bios\): Eden can't start a game without them.
  _keysInto(c, p.join(user, 'keys'), [
    ['prod.keys'],
    ['title.keys'],
  ]);
  _qtGameDirs(c, p.join(user, 'config', 'qt-config.ini'));
}

void _azahar(LaunchContext c) {
  final user = p.join(c.data, 'user');
  // aes_keys.txt for encrypted games, seeddb.bin when there is one.
  _keysInto(c, p.join(user, 'sysdata'), [
    ['aes_keys.txt'],
    ['seeddb.bin'],
  ]);
  _qtGameDirs(c, p.join(user, 'config', 'qt-config.ini'));
}

/// The profile's MLC (Wii U NAND, with the saves): never shared.
String cemuMlc(LaunchContext c) => p.join(c.data, 'mlc01');

void _cemu(LaunchContext c) {
  final portable = p.join(c.data, 'portable');
  io.Directory(c.guard.check(cemuMlc(c))).createSync(recursive: true);
  // A settings.xml beside the exe (an install from before Cemu 2.0) would
  // win over portable\: it's turned off, never deleted.
  final stray = io.File(p.join(c.exeDir, 'settings.xml'));
  if (stray.existsSync()) stray.renameSync(c.guard.check('${stray.path}.gargosy-off'));
  _keysInto(c, portable, [
    ['keys.txt'],
  ]);
  final settings = io.File(p.join(portable, 'settings.xml'));
  if (settings.existsSync() && c.gameFolders.isNotEmpty) {
    final text = settings.readAsStringSync();
    final updated = addCemuGamePaths(text, c.gameFolders);
    if (updated != text) io.File(c.guard.check(settings.path)).writeAsStringSync(updated);
  }
}

/// [xml] (Cemu's settings.xml) with [paths] in `<GamePaths>` as `<Entry>`s;
/// paths already there and everything else stay as they are.
String addCemuGamePaths(String xml, List<String> paths) {
  String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  final have = RegExp(r'<Entry>([^<]*)</Entry>').allMatches(xml).map((m) => m[1]!.toLowerCase()).toSet();
  final add = [for (final path in paths) if (!have.contains(esc(path).toLowerCase())) '<Entry>${esc(path)}</Entry>'];
  if (add.isEmpty) return xml;
  final open = RegExp(r'<GamePaths\s*/>|<GamePaths>').firstMatch(xml);
  if (open != null) {
    final selfClosing = open[0]!.endsWith('/>');
    final inner = add.join();
    return selfClosing
        ? xml.replaceRange(open.start, open.end, '<GamePaths>$inner</GamePaths>')
        : xml.replaceRange(open.end, open.end, inner);
  }
  final close = xml.lastIndexOf('</content>');
  if (close < 0) return xml;
  return xml.replaceRange(close, close, '<GamePaths>${add.join()}</GamePaths>');
}

void _melonDs(LaunchContext c) {
  final portable = p.join(c.data, 'portable');
  final toml = io.File(p.join(portable, 'melonDS.toml'));
  var text = toml.existsSync() ? toml.readAsStringSync() : '';
  // Per instance (melonDS' localCfg): never `<rom>.sav` next to the ROM.
  text = setTomlKeys(text, 'Instance0', {
    'SaveFilePath': p.join(portable, 'saves'),
    'SavestatePath': p.join(portable, 'states'),
  });
  // The shared BIOS and firmware, only the files that are there.
  final bios = <String, String>{
    for (final (key, names) in const [
      ('BIOS9Path', ['bios9.bin']),
      ('BIOS7Path', ['bios7.bin']),
      ('FirmwarePath', ['firmware.bin']),
    ])
      if (findBiosFile(c.bios, names) case final f?) key: f.path,
  };
  if (bios.isNotEmpty) text = setTomlKeys(text, 'DS', bios);
  io.Directory(c.guard.check(portable)).createSync(recursive: true);
  io.File(c.guard.check(toml.path)).writeAsStringSync(text);
}
