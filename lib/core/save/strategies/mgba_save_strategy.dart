// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy: StateSyncCapable (#61): `<ROM stem>.ss<N>` in the profile's states folder.
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';

import '../../platform/platform_info.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../../storage/profile_rooted.dart';
import '../save_state_info.dart';
import '../save_strategy.dart';
import '../state_sync_capable.dart';
import 'mgba_state_file.dart';

/// Save strategy for mGBA (GBA/GBC/GB).
///
/// Checks the RetroArch save directory as fallback for users running
/// RetroArch with the mGBA core.
class MgbaSaveStrategy extends SaveStrategy with StateSyncCapable {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;
  String? _cachedRetroarchDir;

  MgbaSaveStrategy(this._directoryService, {PlatformInfo? platform}) : _platform = platform ?? PlatformInfo.current;

  @override
  String get strategyId => 'mgba';

  @override
  bool get shouldZip => false;

  // ─── Save states (Gargosy, #61) ──────────────────────────────────────────
  //
  // mGBA names a state `<ROM stem>.ss<N>` (src/core/core.c), slots 1–9 from
  // its menu and 0 for its own use. In a profile mGBA is started with
  // `-C savestatePath=<data>\states`; elsewhere it keeps them beside the ROM.

  static final _slotPattern = RegExp(r'\.ss(\d)$');

  @override
  Future<String> stateDirectory(Game game, String romPath) async {
    if (_directoryService is ProfileRootedDirectories) {
      return p.join(await _directoryService.getEmulatorAppSupportDirectory('mgba'), 'states');
    }
    return io.File(romPath).parent.path;
  }

  /// The ROM's stem, as mGBA names the state: the file started (a zip's own
  /// name, mGBA opens zips itself) or RomM's file name.
  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async {
    final stems = {
      p.basenameWithoutExtension(romPath).toLowerCase(),
      if (game.fsName case final fs?) p.basenameWithoutExtension(fs).toLowerCase(),
    }..removeWhere((s) => s.isEmpty);
    if (stems.isEmpty) return null;
    return (String fileName) {
      if (fileName != p.basename(fileName) || fileName.contains(r'\')) return false;
      final m = _slotPattern.firstMatch(fileName);
      return m != null && stems.contains(fileName.substring(0, m.start).toLowerCase());
    };
  }

  @override
  bool looksLikeValidState(Uint8List bytes) => MgbaStateFile.looksValid(bytes);

  @override
  StateSlot slotOf(String fileName) {
    final m = _slotPattern.firstMatch(fileName);
    return m == null ? UnknownStateSlot(fileName) : NumberedStateSlot(int.parse(m.group(1)!));
  }

  /// A state saved with its screenshot is a PNG: the file is the picture.
  @override
  Future<Uint8List?> stateScreenshot(io.File file) async {
    try {
      final bytes = await file.readAsBytes();
      return MgbaStateFile.isPng(bytes) ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    // Gargosy: with a profile's folders, saves live in the profile (mGBA is
    // started with -C savegamePath=<data>\saves), never next to the ROM:
    // roms\ holds only ROMs. Anything else keeps Freegosy's lookup below.
    if (_directoryService is ProfileRootedDirectories) {
      return p.join(await _directoryService.getEmulatorAppSupportDirectory('mgba'), 'saves');
    }
    if (_platform.isLinux) {
      final emuDir = await _directoryService.getEmulatorAppSupportDirectory('mgba');
      if (await io.Directory(emuDir).exists()) return emuDir;
    }

    // 1. ROM-adjacent (standalone mGBA)
    final romDir = io.File(romPath).parent.path;
    if (await io.Directory(romDir).exists()) {
      final stem = p.basenameWithoutExtension(romPath).toLowerCase();
      final dir = io.Directory(romDir);
      await for (final entity in dir.list()) {
        if (entity is io.File) {
          final fname = p.basename(entity.path).toLowerCase();
          if (fname == '$stem.sav' || fname == '$stem.srm') return romDir;
        }
      }
    }

    // 2. Fallback: RetroArch mGBA core save directory
    _cachedRetroarchDir ??= await SaveStrategy.retroarchCoreSaveDir(_directoryService, 'mGBA', platform: _platform);
    if (_cachedRetroarchDir != null) return _cachedRetroarchDir;

    // 3. Absolute fallback: ROM directory
    return romDir;
  }

  @override
  Future<List<io.File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];

    final romStem = p.basenameWithoutExtension(romPath).toLowerCase();
    final fallbackStem = getRomStem(game).toLowerCase();
    final stemWords = romStem.replaceAll(RegExp(r'[^a-z0-9]'), ' ').split(' ').where((w) => w.length >= 3).toList();

    final dir = io.Directory(saveDir);
    if (!await dir.exists()) return [];

    final List<io.File> foundFiles = [];
    await for (final entity in dir.list()) {
      if (entity is! io.File) continue;
      final fname = p.basename(entity.path).toLowerCase();
      if (fname == '$romStem.sav' ||
          fname == '$fallbackStem.sav' ||
          fname == '$romStem.srm' ||
          fname == '$fallbackStem.srm') {
        if (sessionStart != null) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
        }
        foundFiles.add(entity);
        break;
      }
    }

    // Fuzzy fallback: match by word tokens (e.g. "Dragon Ball Z: Legacy" matches "Dragon Ball Z - Legacy.srm")
    if (foundFiles.isEmpty && stemWords.isNotEmpty) {
      await for (final entity in dir.list()) {
        if (entity is! io.File) continue;
        final fname = p.basename(entity.path).toLowerCase();
        if (!fname.endsWith('.srm') && !fname.endsWith('.sav')) continue;
        if (stemWords.any((word) => fname.contains(word))) {
          if (sessionStart != null) {
            final stat = await entity.stat();
            if (stat.modified.isBefore(sessionStart.subtract(const Duration(seconds: 2)))) continue;
          }
          foundFiles.add(entity);
          break;
        }
      }
    }

    return foundFiles;
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) return false;

      final romStem = p.basenameWithoutExtension(destPath).toLowerCase();
      final fallbackStem = getRomStem(game).toLowerCase();
      String targetPath = p.normalize(p.join(saveDir, '$romStem.sav'));

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final file in archive) {
          if (!file.isFile) continue;
          if (file.name == 'freegosy_sync.txt') continue;
          if (file.name.toLowerCase().endsWith('.sav')) {
            await io.Directory(p.dirname(targetPath)).create(recursive: true);
            await backupSave(targetPath);
            await io.File(targetPath).writeAsBytes(file.content);
            return true;
          }
        }
        return true;
      }

      final dir = io.Directory(saveDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is! io.File) continue;
          final fname = p.basename(entity.path).toLowerCase();
          if (fname == '$romStem.sav' ||
              fname == '$fallbackStem.sav' ||
              fname == '$romStem.srm' ||
              fname == '$fallbackStem.srm') {
            targetPath = entity.path;
            break;
          }
        }
        // Fuzzy fallback if strict match failed
        if (targetPath == p.normalize(p.join(saveDir, '$romStem.sav'))) {
          final stemWords = romStem
              .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
              .split(' ')
              .where((w) => w.length >= 3)
              .toList();
          if (stemWords.isNotEmpty) {
            await for (final entity in dir.list()) {
              if (entity is! io.File) continue;
              final fname = p.basename(entity.path).toLowerCase();
              if (!fname.endsWith('.srm') && !fname.endsWith('.sav')) continue;
              if (stemWords.any((word) => fname.contains(word))) {
                targetPath = entity.path;
                break;
              }
            }
          }
        }
      }

      await io.Directory(p.dirname(targetPath)).create(recursive: true);
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }
}
