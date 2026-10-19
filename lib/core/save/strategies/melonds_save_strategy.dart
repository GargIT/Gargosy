// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy: StateSyncCapable (#65): `<ROM stem>.ml<N>` in portable\states;
// melonDS can't load a state from its command line, so states sync only.
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';

import '../../platform/platform_info.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../../storage/profile_rooted.dart';
import '../save_state_info.dart';
import '../save_strategy.dart';
import '../state_sync_capable.dart';

/// Save strategy for melonDS (Nintendo DS).
///
/// Checks the RetroArch save directory as fallback for users running
/// RetroArch with the melonDS / DeSmuME core.
class MelonDsSaveStrategy extends SaveStrategy with StateSyncCapable {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;
  String? _cachedRetroarchDir;

  MelonDsSaveStrategy(this._directoryService, {PlatformInfo? platform}) : _platform = platform ?? PlatformInfo.current;

  @override
  String get strategyId => 'melonds';

  @override
  bool get shouldZip => false;

  // ─── Save states (Gargosy, #65) ──────────────────────────────────────────
  //
  // melonDS names a state `<ROM stem>.ml<N>` in its SavestatePath
  // (src/frontend/qt_sdl/EmuInstance.cpp, getSavestateName), slots 1–8 from
  // its menu; Gargosy sets that path to <data>\portable\states (#15). A state
  // starts `MELN` and its version (src/Savestate.cpp).

  static final _slotSuffix = RegExp(r'\.ml(\d)$');

  @override
  Future<String> stateDirectory(Game game, String romPath) async {
    if (_directoryService is! ProfileRootedDirectories) {
      throw StateError("melonDS's state folder is only known in a Gargosy profile");
    }
    return p.join(await _directoryService.getEmulatorAppSupportDirectory('melonds'), 'portable', 'states');
  }

  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async {
    final stems = {
      p.basenameWithoutExtension(romPath).toLowerCase(),
      if (game.fsName case final fs?) p.basenameWithoutExtension(fs).toLowerCase(),
    }..removeWhere((s) => s.isEmpty);
    if (stems.isEmpty) return null;
    return (String fileName) {
      if (fileName != p.basename(fileName) || fileName.contains(r'\')) return false;
      final m = _slotSuffix.firstMatch(fileName);
      return m != null && stems.contains(fileName.substring(0, m.start).toLowerCase());
    };
  }

  @override
  bool looksLikeValidState(Uint8List bytes) =>
      bytes.length >= 16 && String.fromCharCodes(bytes.sublist(0, 4)) == 'MELN';

  @override
  StateSlot slotOf(String fileName) {
    final m = _slotSuffix.firstMatch(fileName);
    return m == null ? UnknownStateSlot(fileName) : NumberedStateSlot(int.parse(m.group(1)!));
  }

  /// The state format the header records (`14.x`).
  @override
  Future<StateFileInfo> describeState(io.File file) async {
    final base = await super.describeState(file);
    String? format;
    io.RandomAccessFile? raf;
    try {
      raf = await file.open();
      final head = await raf.read(16);
      if (looksLikeValidState(head)) {
        final d = ByteData.sublistView(head);
        format = '${d.getUint16(4, Endian.little)}.${d.getUint16(6, Endian.little)}';
      }
    } catch (e) {
      debugPrint('[melonDS] cannot read the state header of ${file.path}: $e');
    } finally {
      await raf?.close();
    }
    return StateFileInfo(savedAt: base.savedAt, formatId: format);
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    debugPrint('[SaveSync] [melonDS] getSaveDir: romPath=$romPath');

    // Gargosy: in a profile, melonDS saves into <data>\portable\saves (its
    // melonDS.toml sets Instance0.SaveFilePath, issue #15), never next to
    // the ROM: roms\ holds only ROMs.
    if (_directoryService is ProfileRootedDirectories) {
      return p.join(await _directoryService.getEmulatorAppSupportDirectory('melonds'), 'portable', 'saves');
    }

    if (_platform.isLinux) {
      final emuDir = await _directoryService.getEmulatorAppSupportDirectory('melonds');
      if (await io.Directory(emuDir).exists()) {
        debugPrint('[SaveSync] [melonDS]   → Linux melonDS dir: $emuDir');
        return emuDir;
      }
      debugPrint('[SaveSync] [melonDS]   Linux melonDS dir not found: $emuDir');
      // Also check the RetroArch save dir on Linux
      _cachedRetroarchDir ??= await SaveStrategy.retroarchCoreSaveDir(_directoryService, 'NDS', platform: _platform);
      if (_cachedRetroarchDir != null && await io.Directory(_cachedRetroarchDir!).exists()) {
        debugPrint('[SaveSync] [melonDS]   → Linux RetroArch fallback: $_cachedRetroarchDir');
        return _cachedRetroarchDir;
      }
    }

    final romDir = io.File(romPath).parent.path;
    final stems = _stems(game, romPath);

    // Standalone melonDS keeps `<rom>.sav` next to the ROM by default, so a
    // save found anywhere else wins only if it really is this game's.
    final candidates = <String>[romDir];
    if (_platform.isWindows) {
      final appData = _platform.environment['APPDATA'] ?? '';
      final userProfile = _platform.environment['USERPROFILE'] ?? '';
      if (appData.isNotEmpty) {
        candidates.addAll([p.join(appData, 'melonDS'), p.join(appData, 'melonds')]);
      }
      if (userProfile.isNotEmpty) candidates.add(p.join(userProfile, 'Documents', 'melonDS'));
    } else if (_platform.isMacOS) {
      final home = _platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) candidates.add(p.join(home, 'Library', 'Application Support', 'melonDS'));
    }
    for (final dir in candidates) {
      if (await _findSave(dir, stems) != null) {
        debugPrint('[SaveSync] [melonDS]   → existing save in $dir');
        return dir;
      }
    }

    debugPrint('[SaveSync] [melonDS]   → ROM directory: $romDir');
    return romDir;
  }

  Set<String> _stems(Game game, String romPath) => {p.basenameWithoutExtension(romPath), getRomStem(game)};

  /// This game's save in [dir], matched on the exact ROM name only (a title
  /// word shared with another game must never match).
  Future<io.File?> _findSave(String dir, Set<String> stems, {DateTime? sessionStart}) async {
    final d = io.Directory(dir);
    if (!await d.exists()) return null;
    await for (final entity in d.list()) {
      if (entity is! io.File) continue;
      if (!SaveStrategy.saveNameMatchesRom(p.basename(entity.path), stems)) continue;
      if (sessionStart != null &&
          (await entity.stat()).modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) {
        continue;
      }
      return entity;
    }
    return null;
  }

  @override
  Future<List<io.File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) {
      debugPrint('[SaveSync] [melonDS] getSaveFiles: no save dir found');
      return [];
    }

    final found = await _findSave(saveDir, _stems(game, romPath), sessionStart: sessionStart);
    if (found == null) {
      debugPrint('[SaveSync] [melonDS]   no save for this game in $saveDir');
      return [];
    }
    debugPrint('[SaveSync] [melonDS]   → match: ${found.path}');
    return [found];
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) {
        debugPrint('[SaveSync] [melonDS] restoreSave: no save dir');
        return false;
      }

      final romStem = p.basenameWithoutExtension(destPath);
      final existing = await _findSave(saveDir, _stems(game, destPath));
      final targetPath = existing?.path ?? p.normalize(p.join(saveDir, '$romStem.sav'));
      debugPrint('[SaveSync] [melonDS] restoreSave: filename=$filename  target=$targetPath');

      Uint8List? bytes;
      final lower = filename.toLowerCase();
      if (lower.endsWith('.zip')) {
        for (final file in ZipDecoder().decodeBytes(data)) {
          final n = file.name.toLowerCase();
          if (file.isFile && (n.endsWith('.sav') || n.endsWith('.srm'))) {
            bytes = Uint8List.fromList(file.content);
            break;
          }
        }
        if (bytes == null) {
          debugPrint('[SaveSync] [melonDS]   ZIP contained no .sav/.srm files');
          return true;
        }
      } else {
        bytes = data;
      }

      await io.Directory(p.dirname(targetPath)).create(recursive: true);
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(bytes);
      return true;
    } catch (e) {
      debugPrint('[SaveSync] [melonDS] restoreSave ERROR: $e');
      return false;
    }
  }
}
