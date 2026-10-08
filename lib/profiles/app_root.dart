import 'dart:io' as io;

import 'package:path/path.dart' as p;

/// Gargosy's folder: the folder of `Gargosy.exe`, or `--root=<dir>` while
/// developing. Everything Gargosy keeps lives under it (spec §3).
class AppRoot {
  AppRoot(String root) : root = p.normalize(p.absolute(root));

  factory AppRoot.fromArgs(List<String> args, String executablePath) {
    for (final a in args) {
      if (a.startsWith('--root=')) return AppRoot(a.substring('--root='.length));
    }
    return AppRoot(p.dirname(executablePath));
  }

  final String root;

  String get roms => p.join(root, 'roms');
  String get emulators => p.join(root, 'emulators');
  String get bios => p.join(root, 'bios');
  String get userdata => p.join(root, 'userdata');
  String get settingsFile => p.join(userdata, 'settings.json');
  String get templates => p.join(userdata, 'templates');
  String get profiles => p.join(userdata, 'profiles');

  /// Plugin data `path_provider` asks for (support, temp, cache).
  String get appData => p.join(userdata, 'app');

  /// Creates the folders and proves `userdata\` can be written.
  /// Throws [io.FileSystemException] when it can't.
  Future<void> ensureLayout() async {
    for (final dir in [roms, emulators, bios, userdata, templates, profiles, appData]) {
      await io.Directory(dir).create(recursive: true);
    }
    final probe = io.File(p.join(userdata, '.write-test'));
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
  }
}
