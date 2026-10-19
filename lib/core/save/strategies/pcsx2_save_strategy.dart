// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../platform/platform_info.dart';
import '../../romm/game_id_resolver.dart';
import '../../romm/romm_models.dart';
import '../../storage/app_preferences.dart';
import '../../storage/directory_service.dart';
import '../save_state_info.dart';
import '../save_strategy.dart';
import '../state_sync_capable.dart';
import 'pcsx2_state_file.dart';
import '../../../sigil/rom_game_ids.dart';

/// PCSX2 (PlayStation 2): its save states; the memory cards sync through
/// sigil (#57).
/// States: {systemDir}/sstates/{SERIAL (CRC).NN.p2s}, through
/// [StateSyncCapable] / StateSyncService.
class Pcsx2SaveStrategy extends SaveStrategy with StateSyncCapable {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;
  final RomGameIds _gameIds;

  Pcsx2SaveStrategy(this._directoryService, AppPreferences prefs, {PlatformInfo? platform, RomGameIds? gameIds})
    : _platform = platform ?? PlatformInfo.current,
      _gameIds = gameIds ?? RomGameIds(prefs);

  @override
  String get strategyId => 'pcsx2';

  /// The game's PS2 serial (e.g. "SLUS-12345"): RomM's, else read from the
  /// ROM through sigil ([RomGameIds]). Null if neither has it.
  Future<String?> _serial(Game game, String romPath) => GameIdResolver.resolve(
    label: 'PCSX2 ${game.name}',
    server: GameIdResolver.discSerial(game, romPath),
    shape: GameIdResolver.ps1ps2Serial,
    local: () => _gameIds.discSerial(romPath, platform: 'ps2'),
  );

  String _getEmuExe() {
    if (_platform.isWindows) return 'pcsx2-qt.exe';
    if (_platform.isMacOS) return 'PCSX2.app/Contents/MacOS/PCSX2';
    return 'pcsx2-qt';
  }

  /// PCSX2's own state naming: `SERIAL (CRC).NN.p2s` or
  /// `SERIAL (CRC).resume.p2s` (VMManager::GetSaveStateFileName). The
  /// character class excludes path separators; `.p2s.backup` doesn't match.
  static final _stateFilePattern = RegExp(r'^([A-Za-z0-9_-]+) \([0-9A-Fa-f]{8}\)\.(?:\d{2}|resume)\.p2s$');

  static String _serialKey(String serial) => serial.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  @override
  Future<String> stateDirectory(Game game, String romPath) async {
    final root = await _getSaveRoot();
    final isEmuDeck = p.basename(root) == 'saves';
    return isEmuDeck ? p.join(p.dirname(root), 'states') : p.join(root, 'sstates');
  }

  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async {
    final serial = await _serial(game, romPath);
    if (serial == null) return null;
    final wanted = _serialKey(serial);
    return (String fileName) {
      final match = _stateFilePattern.firstMatch(fileName);
      return match != null && _serialKey(match.group(1)!) == wanted;
    };
  }

  /// `.p2s` files are zip archives: they start with a local file header
  /// (`PK\x03\x04`) and end with an end-of-central-directory record
  /// (`PK\x05\x06`, 22 bytes plus a comment of up to 64 KiB). Checking both
  /// ends also rejects a write that was cut off partway.
  @override
  bool looksLikeValidState(Uint8List bytes) {
    if (bytes.length < 26 || bytes[0] != 0x50 || bytes[1] != 0x4B || bytes[2] != 0x03 || bytes[3] != 0x04) {
      return false;
    }
    final earliest = math.max(4, bytes.length - 22 - 0xFFFF);
    for (var i = bytes.length - 22; i >= earliest; i--) {
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06) {
        return true;
      }
    }
    return false;
  }

  static final _slotPattern = RegExp(r'\.(\d{2}|resume)\.p2s$');

  @override
  StateSlot slotOf(String fileName) {
    final match = _slotPattern.firstMatch(fileName);
    if (match == null || !_stateFilePattern.hasMatch(fileName)) {
      return UnknownStateSlot(fileName);
    }
    final slot = match.group(1)!;
    return slot == 'resume' ? const AutoStateSlot() : NumberedStateSlot(int.parse(slot));
  }

  @override
  Future<StateFileInfo> describeState(io.File file) async {
    final base = await super.describeState(file);
    final header = await Pcsx2StateFile.readVersion(file);
    return StateFileInfo(savedAt: base.savedAt, emulatorVersion: header?.version, formatId: header?.formatId);
  }

  @override
  Future<Uint8List?> stateScreenshot(io.File file) => Pcsx2StateFile.readScreenshot(file);

  Future<String> _getSaveRoot() async {
    // 1. Check portable mode first — memcards folder next to exe (Windows)
    final exePath = await _directoryService.findEmulatorExecutable('pcsx2', _getEmuExe());
    if (exePath != null) {
      String exeDir = io.File(exePath).parent.path;
      if (_platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
        exeDir = io.File(exePath).parent.parent.parent.parent.path;
      } else if (await io.FileSystemEntity.isDirectory(exePath)) {
        exeDir = exePath;
      }
      final portableMemcards = p.join(exeDir, 'memcards');
      debugPrint('[PCSX2] exe=$exePath → checking portable memcards at: $portableMemcards');
      if (await io.Directory(portableMemcards).exists()) {
        debugPrint('[PCSX2] portable save root found: $exeDir');
        return exeDir;
      }
      debugPrint('[PCSX2] portable memcards missing at: $portableMemcards');
    } else {
      debugPrint('[PCSX2] no pcsx2 executable found via DirectoryService');
    }

    // 2. Linux integration (EmuDeck / RetroDECK)
    if (_platform.isLinux) {
      final baseDir = await _directoryService.getEmulatorAppSupportDirectory('pcsx2');
      final bool isEmuDeck = _directoryService.linuxSyncPreset == 'emudeck' || baseDir.contains('Emulation/saves');

      if (isEmuDeck) {
        // EmuDeck: saves are in Emulation/saves/pcsx2/saves
        if (p.basename(baseDir) == 'saves') return baseDir;
        final candidate = p.join(baseDir, 'saves');
        if (await io.Directory(candidate).exists()) return candidate;
        return baseDir;
      }

      if (_directoryService.linuxSyncPreset == 'retrodeck') {
        // RetroDECK: PCSX2/memcards/
        return baseDir;
      }

      final home = _platform.environment['HOME'] ?? '';
      final linuxPath = p.join(home, '.config', 'PCSX2');
      if (await io.Directory(p.join(linuxPath, 'memcards')).exists()) {
        return linuxPath;
      }
    }

    // 3. macOS: ~/Library/Application Support/PCSX2
    if (_platform.isMacOS) {
      final home = _platform.environment['HOME'] ?? '';
      final macPath = p.join(home, 'Library', 'Application Support', 'PCSX2');
      if (await io.Directory(p.join(macPath, 'memcards')).exists()) {
        return macPath;
      }
    }

    // 4. Fall back to app support directory
    final resolvedPath = await _directoryService.getEmulatorAppSupportDirectory('pcsx2');
    debugPrint('[PCSX2] app support save root candidate: $resolvedPath');
    if (!await io.Directory(resolvedPath).exists() && !resolvedPath.contains('Emulation/saves')) {
      throw Exception(
        'Save directory not found for PCSX2 at $resolvedPath. Please launch PCSX2 at least once to generate save data.',
      );
    }
    return resolvedPath;
  }

  // Gargosy (#57): PCSX2's saves (the memory cards) go through sigil, which
  // covers every PS2 game (SigilSaveStrategy); this strategy is for states
  // and for telling whether a pull must finish before launch.
  @override
  Future<String?> getSaveDir(Game game, String romPath) async => null;

  @override
  Future<List<io.File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async => const [];

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async => false;

  /// PCSX2's memory cards in [memcardsDir]: `.ps2` files (file cards) and
  /// directories (folder cards), without timestamped backup copies, in name
  /// order (Mcd001.ps2 first).
  Future<List<io.FileSystemEntity>> _memcards(String memcardsDir) async {
    final dir = io.Directory(memcardsDir);
    if (!await dir.exists()) return const [];
    final cards = <io.FileSystemEntity>[];
    await for (final e in dir.list()) {
      final name = p.basename(e.path);
      if ((e is io.File || e is io.Directory) && name.toLowerCase().endsWith('.ps2') && !name.contains('[')) {
        cards.add(e);
      }
    }
    cards.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
    return cards;
  }

  Future<String> _memcardsDir() async {
    final root = await _getSaveRoot();
    return p.basename(root) == 'saves' ? root : p.join(root, 'memcards');
  }

  /// PCSX2 opens its file cards when a game starts, so a pull that lands
  /// after that would be overwritten when the game saves.
  @override
  Future<bool> pullMustFinishBeforeLaunch(Game game, String romPath) async {
    try {
      return (await _memcards(await _memcardsDir())).any((c) => c is io.File);
    } catch (_) {
      return false;
    }
  }
}
