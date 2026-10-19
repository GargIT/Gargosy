// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy: StateSyncCapable (#60): states in StateSaves\, the game by its
// disc id (RomM's, the disc's, else sigil's), Resume with `-s` (DolphinStrategy).
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import '../../platform/platform_info.dart';
import '../../romm/game_id_resolver.dart';
import '../../romm/romm_models.dart';
import '../../storage/directory_service.dart';
import '../../../sigil/rom_game_ids.dart';
import '../../../sigil/sigil_engine.dart';
import '../save_state_info.dart';
import '../save_strategy.dart';
import '../state_sync_capable.dart';
import 'dolphin_state_file.dart';

/// Save strategy for Dolphin emulator (GameCube / Wii).
///
/// Refined to support macOS and Windows user directories and Wii/GC specific paths.
class DolphinSaveStrategy extends SaveStrategy with StateSyncCapable {
  // ignore: unused_field
  final DirectoryService _directoryService;
  final PlatformInfo _platform;
  final IdentifyRom _identify;

  DolphinSaveStrategy(this._directoryService, {PlatformInfo? platform, IdentifyRom? identify})
    : _platform = platform ?? PlatformInfo.current,
      _identify = identify ?? SigilEngine.identify;

  @override
  String get strategyId => 'dolphin';

  /// Wii saves are directories (title/00010000/`hexId`/) that must be zipped.
  /// GameCube saves are individual .gci files — no zip needed.
  /// We return true so the service always bundles correctly; the restore path
  /// already handles both raw .gci and ZIP extraction.
  @override
  bool get shouldZip => true;

  String _getEmuExe() {
    if (_platform.isWindows) return 'Dolphin.exe';
    if (_platform.isMacOS) return 'Dolphin.app/Contents/MacOS/Dolphin';
    return 'Dolphin';
  }

  /// Returns the base user directory for Dolphin.
  Future<String> _getUserDir({String? platformSlug}) async {
    // 1. Check portable mode first — User folder next to exe
    final exePath = await _directoryService.findEmulatorExecutable('dolphin', _getEmuExe());
    if (exePath != null) {
      String exeDir = io.File(exePath).parent.path;
      if (_platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
        exeDir = io.File(exePath).parent.parent.parent.parent.path;
      } else if (await io.FileSystemEntity.isDirectory(exePath)) {
        exeDir = exePath;
      }
      final portableUser = p.join(exeDir, 'User');
      if (await io.Directory(portableUser).exists()) {
        return portableUser;
      }
    }

    // 2. On Linux, if running via Flatpak, which is the default installation method of Dolphin
    if (_platform.isLinux) {
      final home = _platform.environment['HOME'] ?? '';
      final flatpakPath = "$home/.var/app/org.DolphinEmu.dolphin-emu/data/dolphin-emu";
      if (await io.Directory(flatpakPath).exists()) {
        return flatpakPath;
      }
    }

    // 3. Fall back to app support directory
    final resolvedPath = await _directoryService.getEmulatorAppSupportDirectory('Dolphin', platformSlug: platformSlug);
    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception(
        'Save directory not found for Dolphin at $resolvedPath. Please launch Dolphin at least once to generate save data.',
      );
    }
    return resolvedPath;
  }

  /// Detects region code from [romPath].
  String _detectRegion(String romPath) {
    final upper = romPath.toUpperCase();
    if (upper.contains('EUR') || upper.contains('PAL')) return 'EUR';
    if (upper.contains('JAP') || upper.contains('JPN')) return 'JAP';
    return 'USA';
  }

  /// Normalizes game name for comparison.
  String _normalizeGameName(String name) {
    return name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _isValidGameIdByte(int byte) {
    final c = String.fromCharCode(byte);

    final isUpper = c.codeUnitAt(0) >= 'A'.codeUnitAt(0) && c.codeUnitAt(0) <= 'Z'.codeUnitAt(0);

    final isDigit = c.codeUnitAt(0) >= '0'.codeUnitAt(0) && c.codeUnitAt(0) <= '9'.codeUnitAt(0);

    return isUpper || isDigit;
  }

  /// The game's 4-character disc id (`GZLE`): RomM's (`save_target`, RomM
  /// 5.3+), else read from the `.iso`/`.rvz` file. Null if neither has it.
  @visibleForTesting
  Future<String?> gameIdFor(Game game, String romPath) async =>
      GameIdResolver.server('Dolphin ${game.name}', _rommGameId(game)) ?? await _extractGameId(romPath);

  // ─── Save states (Gargosy, #60) ──────────────────────────────────────────
  //
  // Dolphin names a state `<GameID>.s01`–`.s10` in User\StateSaves, the
  // 6-character Game ID being the disc id and the maker (`GZLE01`). Its
  // `lastState.sav` (the undo of a load), `undo.dtm` and the `.dtm` movies
  // beside states are never synced (Source/Core/Core/State.cpp).

  static final _statePattern = RegExp(r'^([A-Za-z0-9]{4})[A-Za-z0-9]{2}\.s(\d{2})$');

  /// Disc ids sigil read from ROMs this session, by ROM path.
  final _readIds = <String, String>{};

  /// The 4-character disc id states are named by: [gameIdFor], else sigil's.
  Future<String?> _stateGameId(Game game, String romPath) async {
    final id = await gameIdFor(game, romPath).catchError((Object _) => null);
    if (id != null && RegExp(r'^[A-Za-z0-9]{4}').hasMatch(id)) return id.substring(0, 4).toUpperCase();
    final known = _readIds[romPath];
    if (known != null) return known;
    try {
      final platform = game.platformSlug?.toLowerCase() == 'wii' ? 'wii' : 'gamecube';
      final read = (await _identify(romPath, platform: platform))?.rawSerial.toUpperCase() ?? '';
      if (!RegExp(r'^[A-Z0-9]{4}').hasMatch(read)) return null;
      return _readIds[romPath] = read.substring(0, 4);
    } catch (e) {
      debugPrint('[Dolphin] reading the disc id of $romPath failed: $e');
      return null;
    }
  }

  @override
  Future<String> stateDirectory(Game game, String romPath) async =>
      p.join(await _getUserDir(platformSlug: game.platformSlug), 'StateSaves');

  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async {
    final id = await _stateGameId(game, romPath);
    if (id == null) return null;
    return (String fileName) {
      final m = _statePattern.firstMatch(fileName);
      if (m == null || m.group(1)!.toUpperCase() != id) return false;
      final slot = int.parse(m.group(2)!);
      return slot >= 1 && slot <= 10;
    };
  }

  @override
  bool looksLikeValidState(Uint8List bytes) => DolphinStateFile.looksValid(bytes);

  @override
  StateSlot slotOf(String fileName) {
    final m = _statePattern.firstMatch(fileName);
    return m == null ? UnknownStateSlot(fileName) : NumberedStateSlot(int.parse(m.group(2)!));
  }

  @override
  Future<StateFileInfo> describeState(File file) async {
    final base = await super.describeState(file);
    return StateFileInfo(savedAt: base.savedAt, emulatorVersion: await DolphinStateFile.readVersion(file));
  }

  /// RomM's `save_target` as a disc id: GameCube's is the id itself; Wii's
  /// is the id as 8 hex digits. Anything else (a WAD's path) is no disc id.
  static String? _rommGameId(Game game) {
    final target = GameIdResolver.clean(game.saveTarget);
    if (target == null) return null;
    if (game.platformSlug?.toLowerCase() != 'wii') {
      // GCI names carry the 4-character id (01-GZLE-…), whatever RomM sends.
      final id = target.toUpperCase();
      return RegExp(r'^[A-Z0-9]{4}').hasMatch(id) ? id.substring(0, 4) : null;
    }
    if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(target)) return null;
    return String.fromCharCodes([for (var i = 0; i < 8; i += 2) int.parse(target.substring(i, i + 2), radix: 16)]);
  }

  /// Extracts Game ID/Code from file if possible.
  /// Often formatted as [GAMEID] Name.ext or Name [GAMEID].ext
  Future<String?> _extractGameId(String romPath) async {
    // Attempt to read the game ID from the file
    final allowedFileExtensions = [".rvz", ".iso"];
    final fileExtension = p.extension(romPath).toLowerCase();
    if (allowedFileExtensions.contains(fileExtension)) {
      final file = await File(romPath).open(mode: FileMode.read);
      final bytes = Uint8List(4);

      int offset = 0;

      switch (fileExtension) {
        case ".rvz":
          offset = 0x58;
          break;
        case ".iso":
          offset = 0x00;
          break;
      }

      await file.setPosition(offset);
      await file.readInto(bytes);
      await file.close();

      for (final b in bytes) {
        if (!_isValidGameIdByte(b)) {
          return null;
        }
      }

      return ascii.decode(bytes);
    }

    final filename = p.basename(romPath);
    final base = p.basenameWithoutExtension(filename);
    // Look for 4 or 6 character uppercase alphanumeric codes
    final match = RegExp(r'\[([A-Z0-9]{4,6})\]').firstMatch(base);
    if (match != null) return match.group(1);

    // Also try 6 char codes at the start of filename (common in some sets)
    final startMatch = RegExp(r'^([A-Z0-9]{6})').firstMatch(base);
    if (startMatch != null) return startMatch.group(1);

    return null;
  }

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final userDir = await _getUserDir(platformSlug: game.platformSlug);
    final bool isIntegratedEnv =
        _platform.isLinux &&
        (_directoryService.linuxSyncPreset == 'emudeck' || _directoryService.linuxSyncPreset == 'retrodeck');

    final isWii = game.platformSlug?.toLowerCase() == 'wii';

    if (isWii) {
      // Wii saves are in Wii/title/00010000/[TITLE_ID_HEX]
      String? titleId = await gameIdFor(game, romPath);

      final String wiiBase = (isIntegratedEnv && p.basename(userDir).toLowerCase() == 'wii')
          ? userDir
          : p.join(userDir, 'Wii');

      if (titleId != null && titleId.length >= 4) {
        final hexId = titleId.substring(0, 4).codeUnits.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
        final wiiPath = p.join(wiiBase, 'title', '00010000', hexId);
        if (await io.Directory(wiiPath).exists()) return wiiPath;
      }

      return p.join(wiiBase, 'title', '00010000');
    } else {
      // GameCube
      final region = _detectRegion(romPath);
      final String gcBase = (isIntegratedEnv && p.basename(userDir).toLowerCase() == 'gc')
          ? userDir
          : p.join(userDir, 'GC');

      // First, check for GCI folder (preferred for sync)
      final gciPath = p.join(gcBase, region, 'Card A');
      if (await io.Directory(gciPath).exists()) return gciPath;

      // Fallback to the general GC folder for memory cards
      return gcBase;
    }
  }

  @override
  Future<List<io.File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async {
    final rootSaveDir = await getSaveDir(game, romPath);
    if (rootSaveDir == null) return [];

    final isWii = game.platformSlug?.toLowerCase() == 'wii';
    final result = <io.File>[];

    if (syncMode == 'saves' || syncMode == 'both') {
      if (isWii) {
        // For Wii, if we have the specific folder, sync it (SaveSyncService will zip it)
        if (p.basename(rootSaveDir) != '00010000') {
          result.add(io.File(rootSaveDir));
        }
      } else {
        // GameCube save matching
        final dir = io.Directory(rootSaveDir);
        if (await dir.exists()) {
          final gameId = (await gameIdFor(game, romPath))?.toUpperCase();
          final normalizedTarget = _normalizeGameName(game.displayName);

          // Dolphin timestamps backups with [YYYY-MM-DD_HH-MM-SS] in the filename.
          // These are internal backups — never sync them.
          final backupPattern = RegExp(r'\[\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\]');

          io.File? bestGci;
          DateTime? bestGciMtime;

          await for (final entity in dir.list(recursive: true)) {
            if (entity is! io.File) continue;
            final filename = p.basename(entity.path).toUpperCase();

            // 1. Match .gci files
            if (filename.endsWith('.GCI')) {
              // Skip Dolphin's own timestamped backup copies
              if (backupPattern.hasMatch(filename)) continue;

              bool match = false;
              if (gameId != null && filename.contains(gameId)) {
                // Strict game ID match — highest confidence
                match = true;
              } else if (gameId == null) {
                // No ID available — fall back to name match
                final normalizedGci = _normalizeGameName(filename);
                if (normalizedGci.contains(normalizedTarget) || normalizedTarget.contains(normalizedGci)) {
                  match = true;
                }
              }

              if (match) {
                final mtime = (await entity.stat()).modified;
                if (sessionStart == null || mtime.isAfter(sessionStart.subtract(const Duration(seconds: 2)))) {
                  // Keep only the newest matching .gci
                  if (bestGci == null || mtime.isAfter(bestGciMtime!)) {
                    bestGci = entity;
                    bestGciMtime = mtime;
                  }
                }
              }
            }
            // 2. Match Memory Card files (.raw, .mcp) - only if they match region
            else if (filename.startsWith('MEMORYCARDA') && (filename.endsWith('.RAW') || filename.endsWith('.MCP'))) {
              final region = _detectRegion(romPath);
              if (filename.contains(region)) {
                if (sessionStart == null ||
                    (await entity.stat()).modified.isAfter(sessionStart.subtract(const Duration(seconds: 2)))) {
                  result.add(entity);
                }
              }
            }
          }

          if (bestGci != null) result.add(bestGci);
        }
      }
    }

    // Gargosy: states never ride in game saves (issue #30, state-sync plan
    // S0.3); they reach RomM only through StateSyncService.

    return result;
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    try {
      final saveDir = await getSaveDir(game, destPath);
      if (saveDir == null) return false;

      final dir = io.Directory(saveDir);
      if (!await dir.exists()) await dir.create(recursive: true);

      if (filename.toLowerCase().endsWith('.zip')) {
        final archive = ZipDecoder().decodeBytes(data);
        for (final file in archive) {
          if (!file.isFile) continue;
          if (file.name == 'freegosy_sync.txt') continue;
          // Gargosy: a state in an older bundle (issue #30) goes to StateSaves\
          // only when this PC has no file of that name; never over one.
          if (isDolphinStateName(file.name)) {
            await _stateIfMissing(game, file.name, file.content as List<int>, modified: file.lastModDateTime);
            continue;
          }

          final targetPath = p.normalize(p.join(saveDir, file.name));
          await io.Directory(p.dirname(targetPath)).create(recursive: true);
          await backupSave(targetPath);
          await io.File(targetPath).writeAsBytes(file.content);
        }
        return true;
      }

      if (isDolphinStateName(filename)) {
        await _stateIfMissing(game, filename, data);
        return true;
      }
      final targetPath = p.normalize(p.join(saveDir, filename));
      await backupSave(targetPath);
      await io.File(targetPath).writeAsBytes(data);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Gargosy: [name] into StateSaves\ when no file of that name is there.
  Future<void> _stateIfMissing(Game game, String name, List<int> bytes, {DateTime? modified}) async {
    final userDir = await _getUserDir(platformSlug: game.platformSlug);
    await restoreStateIfMissing(p.join(userDir, 'StateSaves'), name, bytes, modified: modified);
  }
}

/// Gargosy: a Dolphin save state's file name as older Freegosy bundles
/// carried them from StateSaves\: `<id>.s01`–`.s10`, a `.sav` (its undo
/// state, `lastState.sav`, and others it matched there), or anything in a
/// `StateSaves` folder. GameCube and Wii saves are `.gci` files and title
/// folders, never `.sav`.
bool isDolphinStateName(String name) {
  final n = name.replaceAll('\\', '/').toLowerCase();
  return RegExp(r'\.s\d{2}$').hasMatch(n) || n.endsWith('.sav') || n.contains('statesaves/');
}
