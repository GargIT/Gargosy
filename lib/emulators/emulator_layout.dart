import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../core/save/formats/ps2_memory_card.dart';
import 'pcsx2_folder_card.dart';

/// Where an emulator's data sits inside a profile's `emulators\<id>\` folder,
/// as Freegosy's save strategies look for it (docs/emulator-profiles.md).
class EmulatorLayout {
  const EmulatorLayout(this.id, {this.saveView = '', this.appSupport = '', this.seed = const [], this.ps2Cards = const [], this.pcsx2FolderCards = const []});

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

  /// PS2 memory cards the emulator makes on its first run: Gargosy makes them
  /// (formatted, 8 MB, as PCSX2 does) when there's none yet, so the first
  /// save from RomM goes onto a real card. Without one, Freegosy's restore
  /// made a bare folder that PCSX2 saw as an empty, unformatted card.
  final List<String> ps2Cards;

  /// PCSX2 folder memory cards (as PCSX2 and Freegosy's sync keep them): a
  /// new one when there's none, and the superblock added to one that lacks
  /// it, so PCSX2 doesn't see an unformatted card. A file card stays.
  final List<String> pcsx2FolderCards;

  /// Creates [seed] and [ps2Cards] under [dataDir]. What's there stays.
  void ensureFolders(String dataDir) {
    for (final s in seed) {
      io.Directory(p.join(dataDir, s)).createSync(recursive: true);
    }
    for (final c in ps2Cards) {
      final path = p.join(dataDir, c);
      if (io.FileSystemEntity.typeSync(path) != io.FileSystemEntityType.notFound) continue;
      io.Directory(p.dirname(path)).createSync(recursive: true);
      io.File(path).writeAsBytesSync(Ps2MemoryCard.formatted());
    }
    for (final c in pcsx2FolderCards) {
      ensurePcsx2FolderCard(p.join(dataDir, c));
    }
  }

  static const _table = {
    'dolphin': EmulatorLayout('dolphin', saveView: '_view', seed: ['GC', 'Wii', 'StateSaves']),
    'pcsx2': EmulatorLayout('pcsx2',
        saveView: 'PCSX2', appSupport: 'PCSX2', seed: ['PCSX2/memcards', 'PCSX2/sstates'], pcsx2FolderCards: ['PCSX2/memcards/Mcd001.ps2']),
    'duckstation': EmulatorLayout('duckstation', seed: ['memcards', 'savestates']),
    'ppsspp': EmulatorLayout('ppsspp', saveView: '_view', seed: ['PSP/SAVEDATA', 'PSP/PPSSPP_STATE', 'PSP/SYSTEM']),
    'retroarch': EmulatorLayout('retroarch', seed: ['saves', 'states'], ps2Cards: ['system/pcsx2/memcards/Mcd001.ps2']),
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
    // --config and --savepath into the profile (issue #11).
    'scummvm': EmulatorLayout('scummvm', seed: ['saves', 'screenshots']),
  };

  static EmulatorLayout of(String id) => _table[id] ?? EmulatorLayout(id);

  /// The emulator id for a name the strategies pass to
  /// `getEmulatorAppSupportDirectory` (`Dolphin`, `DuckStation`, `Cemu` …).
  static String? idForName(String name) {
    final lower = name.toLowerCase();
    return _table.containsKey(lower) ? lower : null;
  }
}
