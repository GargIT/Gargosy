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
  // the profile's own, given with -m; a disc's key beside it joins keys.txt.
  'cemu': LinkedFolderConfig(
    'portable',
    then: _Step(_cemu, args: (c) => ['-m', cemuMlc(c)], game: addCemuDiscKey),
  ),
  // melonDS (DS, #15): `portable\` beside the exe; saves and states set in
  // its melonDS.toml, never next to the ROM.
  'melonds': const LinkedFolderConfig('portable', then: _Step(_melonDs)),
};

/// A settings step: [before] edits the profile's files, [args] are the
/// arguments it adds, [game] readies what the game being started needs.
class _Step extends ProfileLaunchConfig {
  const _Step(this.before, {this.args, this.game});
  final void Function(LaunchContext c) before;
  final List<String> Function(LaunchContext c)? args;
  final void Function(LaunchContext c, String romPath)? game;

  @override
  Future<List<String>> prepare(LaunchContext c) async {
    before(c);
    return args?.call(c) ?? const [];
  }

  @override
  void repoint(LaunchContext c) => before(c);

  @override
  List<String> gameArgs(LaunchContext c, String romPath) {
    game?.call(c, romPath);
    return super.gameArgs(c, romPath);
  }
}

/// The shared key files named [names] copied into [folder] when the profile
/// has none yet. Copies, not links: the emulators add keys to these files
/// themselves, which must not change `bios\` or another profile's; and a
/// profile's own newer keys are never replaced.
void _keysInto(LaunchContext c, String folder, List<List<String>> names, {required List<String> platforms}) {
  final bios = BiosFiles(c.bios);
  for (final alternatives in names) {
    final file = bios.find(alternatives, platforms: platforms);
    if (file != null) copySharedFileIfMissing(file, p.join(folder, p.basename(file.path)), c.guard);
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
  _keysInto(
    c,
    p.join(user, 'keys'),
    [
      ['prod.keys'],
      ['title.keys'],
    ],
    platforms: const ['switch'],
  );
  _qtGameDirs(c, p.join(user, 'config', 'qt-config.ini'));
}

void _azahar(LaunchContext c) {
  final user = p.join(c.data, 'user');
  // aes_keys.txt for encrypted games, seeddb.bin when there is one.
  _keysInto(
    c,
    p.join(user, 'sysdata'),
    [
      ['aes_keys.txt'],
      ['seeddb.bin'],
    ],
    platforms: const ['3ds'],
  );
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
  if (stray.existsSync()) {
    var off = '${stray.path}.gargosy-off';
    for (var n = 2; io.FileSystemEntity.typeSync(off) != io.FileSystemEntityType.notFound; n++) {
      off = '${stray.path}.gargosy-off ($n)'; // an earlier one is never replaced
    }
    stray.renameSync(c.guard.check(off));
  }
  _keysInto(
    c,
    portable,
    [
      ['keys.txt'],
    ],
    platforms: const ['wiiu'],
  );
  final settings = io.File(p.join(portable, 'settings.xml'));
  if (settings.existsSync() && c.gameFolders.isNotEmpty) {
    final text = settings.readAsStringSync();
    final updated = addCemuGamePaths(text, c.gameFolders);
    if (updated != text) io.File(c.guard.check(settings.path)).writeAsStringSync(updated);
  }
}

/// A Wii U disc's key as Redump sets keep it, beside the image
/// (`<name>.key`: 16 bytes, or 32 hex digits), added to the profile's
/// keys.txt: Cemu reads keys only from there, one hex line each. A key the
/// file has already (any case) isn't added again.
void addCemuDiscKey(LaunchContext c, String romPath) {
  final keyFile = io.File(p.setExtension(romPath, '.key'));
  if (!keyFile.existsSync()) return;
  final bytes = keyFile.readAsBytesSync();
  final text = String.fromCharCodes(bytes).trim();
  final key = bytes.length == 16
      ? [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join()
      : RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(text)
      ? text.toLowerCase()
      : null;
  if (key == null) return;
  final keys = io.File(c.guard.check(p.join(c.data, 'portable', 'keys.txt')));
  final had = keys.existsSync() ? keys.readAsStringSync() : '';
  if (had.toLowerCase().contains(key)) return;
  final line = '$key # ${p.basenameWithoutExtension(romPath)}\n';
  keys.parent.createSync(recursive: true);
  keys.writeAsStringSync(had.isEmpty || had.endsWith('\n') ? '$had$line' : '$had\n$line');
}

/// [xml] (Cemu's settings.xml) with [paths] in `<GamePaths>` as `<Entry>`s;
/// paths already there and everything else stay as they are.
String addCemuGamePaths(String xml, List<String> paths) {
  String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  final have = RegExp(r'<Entry>([^<]*)</Entry>').allMatches(xml).map((m) => m[1]!.toLowerCase()).toSet();
  final add = [
    for (final path in paths)
      if (!have.contains(esc(path).toLowerCase())) '<Entry>${esc(path)}</Entry>',
  ];
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
  // The shared BIOS and firmware, only the files that are there (bios\nds
  // first). melonDS uses them only with ExternalBIOSEnable, which needs all
  // three; without them it keeps its built-in FreeBIOS.
  final files = BiosFiles(c.bios);
  final bios = <String, String>{
    for (final (key, names) in const [
      ('BIOS9Path', ['bios9.bin']),
      ('BIOS7Path', ['bios7.bin']),
      ('FirmwarePath', ['firmware.bin']),
    ])
      if (files.find(names, platforms: const ['nds']) case final f?) key: f.path,
  };
  if (bios.isNotEmpty) text = setTomlKeys(text, 'DS', bios);
  if (bios.length == 3) {
    text = setTomlKeys(text, 'Emu', {'ExternalBIOSEnable': 'true'}, bare: const {'ExternalBIOSEnable'});
  }
  io.Directory(c.guard.check(portable)).createSync(recursive: true);
  io.File(c.guard.check(toml.path)).writeAsStringSync(text);
}
