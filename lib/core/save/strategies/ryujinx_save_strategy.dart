// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy: a profile's own Ryujinx folder ([profileRoot], issue #9), and a
// game's save is found as Ryujinx keeps it: each 16-hex folder under
// bis\user\save is one save (not a user), its ExtraData0 names the title,
// and its committed data is in 0\ (Freegosy took the newest folder for a
// "user" and so mixed up games).
import 'dart:io' as io;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../platform/platform_info.dart';
import '../../romm/game_id_resolver.dart';
import '../../romm/romm_models.dart';
import '../save_strategy.dart';

/// Save strategy for Ryujinx (Switch) emulator.
class RyujinxSaveStrategy extends SaveStrategy {
  final PlatformInfo _platform;
  final Future<void> Function(String gameId, String titleId)? onMappingResolved;

  RyujinxSaveStrategy({this.onMappingResolved, PlatformInfo? platform, this.profileRoot})
      : _platform = platform ?? PlatformInfo.current;

  /// Gargosy: the profile's Ryujinx folder (started with `-r` on it, issue
  /// #9); null outside a profile, where %APPDATA%\Ryujinx is looked at.
  final Future<String> Function()? profileRoot;

  @override
  String get strategyId => 'switch_ryujinx';

  @override
  bool get supportsSaveSync => true;

  // ── Regex library ──────────────────────────────────────────────────────────

  static final RegExp _strictTitleIdRegex = RegExp(r'^01[0-9A-Fa-f]{14}$');
  static final RegExp _titleIdExtractorRegex = RegExp(r'01[0-9A-Fa-f]{14}');
  static final RegExp _cnmtRegex = RegExp(r'(01[0-9A-Fa-f]{14})\.cnmt', caseSensitive: false);
  static final RegExp _userIdRegex = RegExp(r'^[0-9A-Fa-f]{16}$');
  static const _romExtensions = ['.nsp', '.xci', '.nsz'];

  // ── Mutable state ──────────────────────────────────────────────────────────

  String? _manualMapping;

  void setManualMapping(String? titleId) => _manualMapping = titleId;
  /// Gargosy: a save is found by its title, not by a user folder, so the
  /// engine's profile choice isn't needed (kept for its callers).
  void setActiveProfileOverride(String? profileId) {}

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 1 — Title ID Resolution
  // ═══════════════════════════════════════════════════════════════════════════

  @visibleForTesting
  Future<String> resolveTitleId(String romPath, Game game) async {
    // RomM's id (RomM 5.3+) first: the header and file name are slower, and
    // the cached mapping below can be stale.
    final fromRomm = _rommTitleId(game);
    if (fromRomm != null) return fromRomm;
    // 1. Header byte scan
    final (fromHeader, resolvedRomPath) = await _extractTitleIdFromHeader(romPath);
    if (fromHeader != null) {
      debugPrint('[Ryujinx] Title ID from header: $fromHeader');
      if (onMappingResolved != null) {
        await onMappingResolved!(game.id, fromHeader);
      }
      return fromHeader;
    }

    // 2. Extract from ROM filename
    final fromFilename = _extractTitleIdFromFilename(resolvedRomPath ?? romPath, game);
    if (fromFilename != null) {
      debugPrint('[Ryujinx] Title ID from filename: $fromFilename');
      if (onMappingResolved != null) {
        await onMappingResolved!(game.id, fromFilename);
      }
      return fromFilename;
    }

    // 3. Manual mapping
    if (_manualMapping != null && _manualMapping!.isNotEmpty) {
      debugPrint('[Ryujinx] Title ID from manual mapping: $_manualMapping');
      return _manualMapping!;
    }

    // 4. Nothing worked
    debugPrint('[Ryujinx] FAILED: No Title ID resolved for ${game.name}');
    throw SaveMappingRequiredException(
        'Could not determine Title ID for "${game.name}". '
        'Please select the save folder manually.');
  }

  String? _extractTitleIdFromFilename(String romPath, Game game) {
    for (final candidate in [p.basename(romPath), game.fileName ?? '', game.name]) {
      if (candidate.isEmpty) continue;
      final match = _titleIdExtractorRegex.firstMatch(candidate);
      if (match != null) {
        return _normalizeToBaseId(match.group(0)!);
      }
    }
    return null;
  }

  Future<(String? titleId, String? resolvedPath)> _extractTitleIdFromHeader(String romPath) async {
    final actualPath = await _resolveRomFile(romPath);
    if (actualPath == null) return (null, null);

    try {
      final file = io.File(actualPath);
      final raf = await file.open();
      final bytes = await raf.read(262144); // 256 KB
      await raf.close();

      final content = String.fromCharCodes(bytes);
      final match = _cnmtRegex.firstMatch(content);
      if (match != null) {
        return (_normalizeToBaseId(match.group(1)!), actualPath);
      }
    } catch (e) {
      debugPrint('[Ryujinx][Scanner] ERROR: $e');
    }
    return (null, actualPath);
  }

  /// RomM's title id (RomM 5.3+) as the base game's, or null.
  static String? _rommTitleId(Game game) {
    final id = GameIdResolver.server('Ryujinx ${game.name}', game.titleId?.toUpperCase(),
        shape: GameIdResolver.switchTitleId);
    return id == null ? null : _normalizeToBaseId(id);
  }

  static String _normalizeToBaseId(String raw) {
    final upper = raw.toUpperCase();
    if (upper.length == 16) {
      return '${upper.substring(0, 13)}000';
    }
    return upper;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  LAYER 2 — User ID / Profile Resolution
  // ═══════════════════════════════════════════════════════════════════════════


  // ═══════════════════════════════════════════════════════════════════════════
  //  ROM file resolution (fuzzy matching)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> _resolveRomFile(String romPath) async {
    if (io.File(romPath).existsSync()) return romPath;
    for (final ext in _romExtensions) {
      final withExt = '$romPath$ext';
      if (io.File(withExt).existsSync()) return withExt;
    }
    if (io.Directory(romPath).existsSync()) return _findLargestRomInDir(romPath);
    return null;
  }

  String? _findLargestRomInDir(String dirPath) {
    io.File? largest;
    int maxSize = -1;
    try {
      for (final entity in io.Directory(dirPath).listSync(recursive: true)) {
        if (entity is! io.File) continue;
        final name = entity.path.toLowerCase();
        if (!_romExtensions.any((ext) => name.endsWith(ext))) continue;
        final size = entity.lengthSync();
        if (size > maxSize) {
          maxSize = size;
          largest = entity;
        }
      }
    } catch (_) {}
    return largest?.path;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Platform-specific save base path
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String> _getRyujinxSaveBase({String? platformSlug}) async {
    final String resolvedPath;
    if (profileRoot != null) {
      resolvedPath = await profileRoot!();
    } else if (_platform.isMacOS) {
      final home = _platform.environment['HOME'] ?? '';
      resolvedPath = p.join(home, 'Library', 'Application Support', 'Ryujinx');
    } else if (_platform.isLinux) {
      final home = _platform.environment['HOME'] ?? '';
      resolvedPath = p.join(home, '.config', 'Ryujinx');
    } else if (_platform.isWindows) {
      final appData = _platform.environment['APPDATA'] ?? '';
      resolvedPath = p.join(appData, 'Ryujinx');
    } else {
      throw UnsupportedError('Platform not supported for Ryujinx save path resolution');
    }

    final finalPath = p.join(resolvedPath, 'bis', 'user', 'save');
    if (!await io.Directory(finalPath).exists()) {
      throw Exception('Save directory not found for Ryujinx at $finalPath.');
    }
    return finalPath;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  Public API — SaveStrategy overrides
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<String?> getSaveDir(Game game, String romPath) async {
    final base = await _getRyujinxSaveBase(platformSlug: game.platformSlug);
    final titleId = await resolveTitleId(romPath, game);
    final folder = saveFolderFor(base, titleId);
    debugPrint('[Ryujinx] getSaveDir: title $titleId -> ${folder ?? 'no save made yet'}');
    return folder == null ? null : p.join(folder, '0');
  }

  /// The folder under [base] (`bis\user\save`) that holds [titleId]'s save,
  /// by its ExtraData0 (or ExtraData1): the title at offset 0 (u64, little
  /// endian), the save type at 0x20 (1 = a user's save). A user's save comes
  /// before a device or cache one; of several, the newest. Null when Ryujinx
  /// hasn't made one yet (the game was never started on this profile).
  @visibleForTesting
  static String? saveFolderFor(String base, String titleId) {
    final dir = io.Directory(base);
    if (!dir.existsSync()) return null;
    final target = _normalizeToBaseId(titleId);
    final found = <({String path, bool account, DateTime modified})>[];
    for (final e in dir.listSync()) {
      if (e is! io.Directory || !_userIdRegex.hasMatch(p.basename(e.path))) continue;
      for (final name in const ['ExtraData0', 'ExtraData1']) {
        final f = io.File(p.join(e.path, name));
        if (!f.existsSync()) continue;
        try {
          final bytes = f.readAsBytesSync();
          if (bytes.length < 0x21) continue;
          final program =
              bytes.sublist(0, 8).reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
          if (_normalizeToBaseId(program) != target) break;
          final committed = io.Directory(p.join(e.path, '0'));
          found.add((
            path: e.path,
            account: bytes[0x20] == 1,
            modified: committed.existsSync() ? committed.statSync().modified : f.statSync().modified,
          ));
          break;
        } catch (err) {
          debugPrint('[Ryujinx] ${f.path}: $err');
        }
      }
    }
    if (found.isEmpty) return null;
    found.sort((a, b) {
      if (a.account != b.account) return a.account ? -1 : 1;
      return b.modified.compareTo(a.modified);
    });
    return found.first.path;
  }

  @override
  Future<List<io.File>> getSaveFiles(Game game, String romPath, {DateTime? sessionStart, String syncMode = 'both'}) async {
    final saveDir = await getSaveDir(game, romPath);
    if (saveDir == null) return [];
    final dir = io.Directory(saveDir);
    if (!dir.existsSync()) return [];

    final files = dir.listSync(recursive: true).whereType<io.File>().where((f) {
      final name = p.basename(f.path);
      return !name.startsWith('.') && !name.endsWith('.bak');
    }).toList();

    if (files.isEmpty) return [];

    if (sessionStart != null) {
      final hasChanges = files.any((f) => f.statSync().modified.isAfter(sessionStart.subtract(const Duration(seconds: 2))));
      if (!hasChanges) return [];
    }

    return [io.File(saveDir)];
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    final titleId = await resolveTitleId(destPath, game);
    final targetPath = await getSaveDir(game, destPath);
    if (targetPath == null) {
      throw Exception("Ryujinx hasn't made a save for ${game.name} ($titleId) on this profile yet: "
          'start the game once, then its save from RomM can be put in place.');
    }

    debugPrint('[Ryujinx] Restore: title $titleId into $targetPath');
    if (!io.Directory(targetPath).existsSync()) {
      io.Directory(targetPath).createSync(recursive: true);
    }

    bool success = false;
    if (filename.toLowerCase().endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(data);
      success = await _extractArchive(archive, targetPath, titleId: titleId);
    } else {
      final filePath = p.normalize(p.join(targetPath, filename));
      await backupSave(filePath);
      await io.File(filePath).writeAsBytes(data);
      success = true;
    }
    return success;
  }

  /// Lists all Title ID save folders for the active profile.
  /// Used by the UI for manual folder selection.
  Future<List<Map<String, dynamic>>> getAvailableSaveFolders() async {
    final base = await _getRyujinxSaveBase();
    final userDir = io.Directory(base); // Gargosy: every save folder is here
    if (!userDir.existsSync()) return [];

    final folders = <Map<String, dynamic>>[];
    for (final entity in userDir.listSync()) {
      if (entity is! io.Directory) continue;
      final name = p.basename(entity.path);
      
      String? displayName = name;
      final extraData = io.File(p.join(entity.path, 'ExtraData0'));
      if (extraData.existsSync()) {
        try {
          final bytes = await extraData.readAsBytes();
          if (bytes.length >= 8) {
            displayName = bytes.sublist(0, 8).reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
          }
        } catch (_) {}
      }

      DateTime? newest;
      int fileCount = 0;
      for (final f in entity.listSync(recursive: true)) {
        if (f is! io.File) continue;
        final fname = p.basename(f.path);
        if (fname == 'ExtraData0' || fname.startsWith('.') || fname.endsWith('.bak')) continue;
        fileCount++;
        final mod = f.statSync().modified;
        if (newest == null || mod.isAfter(newest)) newest = mod;
      }

      if (fileCount > 0) {
        folders.add({
          'name': displayName,
          'path': name, // folder name is the path
          'lastModified': newest ?? entity.statSync().modified,
          'fileCount': fileCount,
        });
      }
    }

    folders.sort((a, b) => (b['lastModified'] as DateTime).compareTo(a['lastModified'] as DateTime));
    return folders;
  }

  Future<bool> _extractArchive(Archive archive, String destDir, {String? titleId}) async {
    for (final entry in archive) {
      if (entry.name.isEmpty || entry.name == 'freegosy_sync.txt' || entry.name.contains('.bak')) continue;
      
      // Strip container folders: Title ID, User ID, or a numeric index (0, 1, 2...).
      final segments = entry.name.split(RegExp(r'[/\\]'));
      var currentSegments = List<String>.from(segments);
      
      while (currentSegments.length > 1) {
        final first = currentSegments.first;
        final isTitleId = _strictTitleIdRegex.hasMatch(first) || (titleId != null && first.toUpperCase() == titleId.toUpperCase());
        final isUserId = _userIdRegex.hasMatch(first);
        final isNumeric = RegExp(r'^\d+$').hasMatch(first);

        if (isTitleId || isUserId || isNumeric) {
          currentSegments.removeAt(0);
        } else {
          break;
        }
      }
      
      final entryPath = p.joinAll(currentSegments);
      if (entryPath.isEmpty) continue;

      debugPrint('[Ryujinx] Restore Entry: "${entry.name}" -> "$entryPath"');
      
      final outPath = p.normalize(p.join(destDir, entryPath));
      if (entry.isFile) {
        await backupSave(outPath);
        final outFile = io.File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>);
      } else {
        await io.Directory(outPath).create(recursive: true);
      }
    }
    return true;
  }
}
