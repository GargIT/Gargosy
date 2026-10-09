import 'dart:io' as io;

import 'package:path/path.dart' as p;

/// Where an emulator's data sits inside a profile's `emulators\<id>\` folder,
/// as Freegosy's save strategies look for it (docs/emulator-profiles.md).
class EmulatorLayout {
  const EmulatorLayout(this.id, {this.saveView = '', this.appSupport = '', this.seed = const []});

  final String id;

  /// The folder the save strategies are told the exe is in, relative to the
  /// profile's data folder. `_view` is a folder that never exists, for
  /// emulators whose "portable install" check must not match.
  final String saveView;

  /// What the strategies get for this emulator's app-support folder.
  final String appSupport;

  /// Folders the emulator makes on its first run. Gargosy makes them before
  /// the first save is put in place, so a new profile's first game already
  /// starts with its RomM save (some strategies refuse a folder that's missing).
  final List<String> seed;

  /// Creates [seed] under [dataDir].
  void ensureFolders(String dataDir) {
    for (final s in seed) {
      io.Directory(p.join(dataDir, s)).createSync(recursive: true);
    }
  }

  static const _table = {
    'dolphin': EmulatorLayout('dolphin', saveView: '_view', seed: ['GC', 'Wii', 'StateSaves']),
    'pcsx2': EmulatorLayout('pcsx2', saveView: 'PCSX2', appSupport: 'PCSX2', seed: ['PCSX2/memcards', 'PCSX2/sstates']),
    'duckstation': EmulatorLayout('duckstation', seed: ['memcards', 'savestates']),
    'ppsspp': EmulatorLayout('ppsspp', saveView: '_view', seed: ['PSP/SAVEDATA', 'PSP/PPSSPP_STATE', 'PSP/SYSTEM']),
    'retroarch': EmulatorLayout('retroarch', seed: ['saves', 'states']),
    'xenia_canary': EmulatorLayout('xenia_canary', seed: ['content']),
    'ares': EmulatorLayout('ares', seed: ['saves']),
    'mgba': EmulatorLayout('mgba', saveView: '_view', seed: ['saves', 'states']),
    'flycast': EmulatorLayout('flycast', seed: ['saves', 'vmu', 'states']),
    'cemu': EmulatorLayout('cemu', saveView: '_view'),
    'eden': EmulatorLayout('eden', saveView: '_view'),
    'azahar': EmulatorLayout('azahar', saveView: '_view'),
    'melonds': EmulatorLayout('melonds', saveView: '_view'),
    'rpcs3': EmulatorLayout('rpcs3', saveView: '_view'),
    'ryujinx': EmulatorLayout('ryujinx', saveView: '_view'),
  };

  static EmulatorLayout of(String id) => _table[id] ?? EmulatorLayout(id);

  /// The emulator id for a name the strategies pass to
  /// `getEmulatorAppSupportDirectory` (`Dolphin`, `DuckStation`, `Cemu` …).
  static String? idForName(String name) {
    final lower = name.toLowerCase();
    return _table.containsKey(lower) ? lower : null;
  }
}
