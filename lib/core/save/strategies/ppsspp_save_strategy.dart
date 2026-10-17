// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy: StateSyncCapable (#59): states in PSP\PPSSPP_STATE, the game by
// its disc id (RomM's, else sigil's), Resume with `--state=`.
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io' show File;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../platform/platform_info.dart';
import '../../romm/game_id_resolver.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../../../sigil/rom_game_ids.dart';
import '../../../sigil/sigil_engine.dart';
import '../save_state_info.dart';
import '../save_strategy.dart';
import '../state_sync_capable.dart';
import 'ppsspp_state_file.dart';

/// Save strategy for PPSSPP (PSP).
class PpssppSaveStrategy extends SaveStrategy with StateSyncCapable {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;
  final IdentifyRom _identify;

  PpssppSaveStrategy(this._directoryService, {PlatformInfo? platform, IdentifyRom? identify})
      : _platform = platform ?? PlatformInfo.current,
        _identify = identify ?? SigilEngine.identify;

  @override
  String get strategyId => 'ppsspp';

  String _getEmuExe() {
    if (_platform.isWindows) return 'PPSSPPWindows64.exe';
    if (_platform.isMacOS) return 'PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL';
    return 'PPSSPPSDL';
  }

  Future<String> _getPspDir({String? platformSlug}) async {
    // 1. Check portable mode first (Windows)
    if (_platform.isWindows) {
      final exePath = await _directoryService.findEmulatorExecutable(
          'ppsspp', _getEmuExe());
      if (exePath != null) {
        final emuDir = io.File(exePath).parent.path;
        final portableDir = p.join(emuDir, 'memstick', 'PSP');
        if (await io.Directory(portableDir).exists()) {
          return portableDir;
        }
      }

      // 1b. Check Documents/PPSSPP/PSP (Windows default)
      final userProfile = _platform.environment['USERPROFILE'] ?? '';
      if (userProfile.isNotEmpty) {
        final docsPsp = p.join(userProfile, 'Documents', 'PPSSPP', 'PSP');
        if (await io.Directory(docsPsp).exists()) {
          return docsPsp;
        }
      }
    }

    // 2. Dynamic path resolution (favors EmuDeck if configured)
    final baseDir = await _directoryService.getEmulatorAppSupportDirectory('ppsspp', platformSlug: platformSlug);
    
    // Check if baseDir is a symlink (typical for EmuDeck)
    String resolvedBase = baseDir;
    try {
      if (await io.FileSystemEntity.isLink(baseDir)) {
        resolvedBase = await io.Link(baseDir).resolveSymbolicLinks();
      }
    } catch (_) {}

    // On Steam Deck, 'saves' symlink points to .../PSP/SAVEDATA.
    // If we resolved it, the PSP root is the parent.
    if (resolvedBase.toUpperCase().endsWith('SAVEDATA')) {
       return p.dirname(resolvedBase);
    }
    
    // Standard folder logic
    if (!resolvedBase.endsWith('PSP')) {
       final pspDir = p.join(resolvedBase, 'PSP');
       if (await io.Directory(pspDir).exists()) return pspDir;
    }

    return resolvedBase;
  }

  /// Reads PARAM.SFO file and extracts the game title.
  Future<String?> _readParamSfoTitle(String folderPath) async {
    try {
      final sfoFile = io.File(p.join(folderPath, 'PARAM.SFO'));
      if (!await sfoFile.exists()) return null;

      final bytes = await sfoFile.readAsBytes();
      if (bytes.length < 20) return null;
      final byteData = ByteData.view(bytes.buffer);

      if (bytes[0] != 0x00 || bytes[1] != 0x50 || bytes[2] != 0x53 || bytes[3] != 0x46) return null;

      final keyTableOffset  = byteData.getUint32(8,  Endian.little);
      final dataTableOffset = byteData.getUint32(12, Endian.little);
      final entriesCount    = byteData.getUint32(16, Endian.little);

      for (int i = 0; i < entriesCount; i++) {
        final entryBase = 20 + i * 16;
        if (entryBase + 16 > bytes.length) break;
        final keyRelOffset  = byteData.getUint16(entryBase + 0,  Endian.little);
        final dataLen       = byteData.getUint32(entryBase + 4,  Endian.little);
        final dataRelOffset = byteData.getUint32(entryBase + 12, Endian.little);

        final keyStart = keyTableOffset + keyRelOffset;
        final keyBytes = <int>[];
        int j = keyStart;
        while (j < bytes.length && bytes[j] != 0) {
          keyBytes.add(bytes[j++]);
        }
        final key = utf8.decode(keyBytes);

        if (key == 'TITLE') {
          final valueStart = dataTableOffset + dataRelOffset;
          final titleBytes = bytes.sublist(valueStart, valueStart + dataLen);
          final nullIdx = titleBytes.indexOf(0);
          return utf8.decode(nullIdx != -1 ? titleBytes.sublist(0, nullIdx) : titleBytes);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Whether a SAVEDATA folder holds game data a game installed from its
  /// disc rather than a save (PPSSPP's install dialog writes those under the
  /// same id). Every save's PARAM.SFO names SAVEDATA_PARAMS and
  /// SAVEDATA_FILE_LIST; an install's names neither. A folder with no
  /// readable PARAM.SFO counts as a save, so nothing is dropped by mistake.
  static Future<bool> _isGameDataInstall(String folderPath) async {
    try {
      final sfo = io.File(p.join(folderPath, 'PARAM.SFO'));
      if (!await sfo.exists() || await sfo.length() > 64 * 1024) return false;
      final text = latin1.decode(await sfo.readAsBytes());
      return !text.contains('SAVEDATA_PARAMS') && !text.contains('SAVEDATA_FILE_LIST');
    } catch (_) {
      return false;
    }
  }

  /// The save folder whose PARAM.SFO title best matches [game]'s name, else
  /// the newest folder: the guess used when RomM doesn't know the game's id.
  Future<List<io.Directory>> _foldersByTitle(List<io.Directory> allSubdirs, Game game) async {
    final foldersWithTitles = <Map<String, dynamic>>[];
    for (final dir in allSubdirs) {
      final title = await _readParamSfoTitle(dir.path);
      if (title != null) {
        foldersWithTitles.add({'dir': dir, 'title': title, 'modified': (await dir.stat()).modified});
      }
    }

    final gameWords = game.name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9\s]"), '').split(' ').where((w) => w.length >= 2).toList();

    // Score each folder by how many game name words appear in its PARAM.SFO title,
    // then pick only the single best-scoring folder to avoid uploading saves from
    // unrelated games that share a common word (e.g. "Grand", "Battle", "War").
    List<io.Directory> foldersToBundle = [];
    if (foldersWithTitles.isNotEmpty) {
      int bestScore = 0;
      io.Directory? bestDir;
      DateTime? bestMtime;
      for (final entry in foldersWithTitles) {
        final title = (entry['title'] as String).toLowerCase();
        final score = gameWords.where((w) => title.contains(w)).length;
        if (score > bestScore ||
            (score == bestScore && bestScore > 0 &&
             (entry['modified'] as DateTime).isAfter(bestMtime!))) {
          bestScore = score;
          bestDir = entry['dir'] as io.Directory;
          bestMtime = entry['modified'] as DateTime;
        }
      }
      if (bestScore > 0 && bestDir != null) {
        foldersToBundle.add(bestDir);
      } else {
        // No title match — fall back to most recently modified folder
        foldersWithTitles.sort((a, b) => (b['modified'] as DateTime).compareTo(a['modified'] as DateTime));
        foldersToBundle.add(foldersWithTitles.first['dir'] as io.Directory);
      }
    }
    return foldersToBundle;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final pspDir = await _getPspDir(platformSlug: game.platformSlug);
    return p.join(pspDir, 'SAVEDATA');
  }

  // ─── Save states (Gargosy, #59) ──────────────────────────────────────────
  //
  // PPSSPP names a state `<DISC_ID>_<DISC_VERSION>_<slot>.ppst` (slot from
  // 0) in PSP\PPSSPP_STATE, with `<same>.jpg` as its screenshot; the undo
  // copies (`<same>.undo.ppst`), slot names (`.name.txt`) and the global
  // `load_undo.ppst` are never synced (Core/SaveState.cpp). Any disc
  // version is the game's: a dump of another version is the same game to RomM.

  static final _statePattern = RegExp(r'^([A-Za-z0-9]+)_(\d+\.\d+)_(\d+)\.ppst$');

  /// Disc ids read from ROMs this session, by ROM path.
  final _discIds = <String, String>{};

  /// The game's disc id (`ULUS10041`): RomM's, else sigil's from the ROM.
  Future<String?> _discId(Game game, String romPath) => GameIdResolver.resolve(
        label: 'PPSSPP ${game.name}',
        server: GameIdResolver.discFolderId('PPSSPP ${game.name}', game),
        local: () async {
          final known = _discIds[romPath];
          if (known != null) return known;
          try {
            final id = (await _identify(romPath, platform: 'psp'))?.titleId.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
            if (id == null || !GameIdResolver.sonyDiscId.hasMatch(id)) return null;
            return _discIds[romPath] = id;
          } catch (e) {
            debugPrint('[PPSSPP] reading the disc id of $romPath failed: $e');
            return null;
          }
        },
      );

  @override
  Future<String> stateDirectory(Game game, String romPath) async =>
      p.join(await _getPspDir(platformSlug: game.platformSlug), 'PPSSPP_STATE');

  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async {
    final id = await _discId(game, romPath);
    if (id == null) return null;
    return (String fileName) {
      final m = _statePattern.firstMatch(fileName);
      return m != null && m.group(1)!.toUpperCase() == id;
    };
  }

  @override
  bool looksLikeValidState(Uint8List bytes) => PpssppStateFile.looksValid(bytes);

  /// PPSSPP counts slots from 0 and shows them from 1.
  @override
  StateSlot slotOf(String fileName) {
    final m = _statePattern.firstMatch(fileName);
    return m == null ? UnknownStateSlot(fileName) : NumberedStateSlot(int.parse(m.group(3)!) + 1);
  }

  @override
  Future<StateFileInfo> describeState(File file) async {
    final base = await super.describeState(file);
    return StateFileInfo(savedAt: base.savedAt, emulatorVersion: await PpssppStateFile.readVersion(file));
  }

  /// The `.jpg` PPSSPP writes beside the state.
  @override
  Future<Uint8List?> stateScreenshot(File file) async {
    try {
      final shot = File(p.setExtension(file.path, '.jpg'));
      return await shot.exists() ? await shot.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<File>> getSaveFiles(Game game, String romPath,
      {DateTime? sessionStart, String syncMode = 'both'}) async {
    final pspDir = await _getPspDir(platformSlug: game.platformSlug);
    final result = <File>[];

    final saveDataDir = io.Directory(p.join(pspDir, 'SAVEDATA'));
    if (await saveDataDir.exists()) {
      final allSubdirs = await saveDataDir.list().where((e) => e is io.Directory).cast<io.Directory>().toList();
      final fromRomm = GameIdResolver.discFolderId('PPSSPP ${game.name}', game);
      final foldersToBundle = fromRomm != null
          ? [
              for (final d in allSubdirs)
                if (p.basename(d.path).toUpperCase().startsWith(fromRomm) && !await _isGameDataInstall(d.path)) d
            ]
          : await _foldersByTitle(allSubdirs, game);

      for (final dir in foldersToBundle) {
        result.add(io.File(dir.path));
      }
    }

    // Gargosy: states never ride in game saves (issue #30); StateSyncService
    // carries them.

    return result;
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final pspDir = await _getPspDir(platformSlug: game.platformSlug);
      final targetSaveDir = p.join(pspDir, 'SAVEDATA');
      final targetStateDir = p.join(pspDir, 'PPSSPP_STATE');

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        await io.Directory(targetSaveDir).create(recursive: true);
        await io.Directory(targetStateDir).create(recursive: true);

        for (final entry in archive) {
          if (entry.name.contains('.bak') || entry.name == 'freegosy_sync.txt') continue;
          
          // SMART FLATTENING: Strip redundant psp/PSP/SAVEDATA prefixes
          String cleanName = entry.name.replaceAll('\\', '/');
          final parts = cleanName.split('/');
          
          // If the ZIP contains "psp/PSP/SAVEDATA/ULUS...", we want just "ULUS..."
          int skipCount = 0;
          for (int i = 0; i < parts.length; i++) {
            final p = parts[i].toUpperCase();
            if (p == 'PSP' || p == 'SAVEDATA' || p == 'PPSSPP_STATE') {
              skipCount = i + 1;
            }
          }
          if (skipCount > 0) {
             cleanName = p.joinAll(parts.sublist(skipCount));
          }
          if (cleanName.isEmpty) continue;

          final targetPath = p.normalize(entry.name.toLowerCase().endsWith('.ppst') 
              ? p.join(targetStateDir, cleanName)
              : p.join(targetSaveDir, cleanName));

          if (entry.isFile && entry.name.toLowerCase().endsWith('.ppst')) {
            // Gargosy: a state in an older bundle (issue #30), only when this
            // PC has none of that name; never over one.
            await restoreStateIfMissing(targetStateDir, entry.name, entry.content as List<int>,
                modified: entry.lastModDateTime);
          } else if (entry.isFile) {
            await backupSave(targetPath);
            final outFile = io.File(targetPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(entry.content as List<int>);
          } else {
            await io.Directory(targetPath).create(recursive: true);
          }
        }
        return true;
      }

      if (filename.toLowerCase().endsWith('.ppst')) {
        // Gargosy: only when this PC has no state of that name (issue #30).
        await restoreStateIfMissing(targetStateDir, filename, data);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[PPSSPP] Restore error: $e');
      rethrow;
    }
  }
}
