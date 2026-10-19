// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy: lints the newer SDK raises on copied code, kept as upstream.
// ignore_for_file: prefer_initializing_formals
import 'dart:io';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../sigil/rom_game_ids.dart';
import '../../platform/platform_info.dart';
import '../../romm/game_id_resolver.dart';
import '../../romm/romm_models.dart';
import '../../storage/app_preferences.dart';
import '../../storage/directory_service.dart';
import '../save_state_info.dart';
import '../save_strategy.dart';
import '../state_sync_capable.dart';
import 'duckstation_config.dart';
import 'duckstation_state_file.dart';

/// DuckStation (PlayStation 1): its save states, and the memory-card setup
/// sigil reads ([sigilCard]); the cards themselves sync through sigil (#57).
/// States: {dataDir}/savestates/{SERIAL}_{N|resume}.sav, through
/// [StateSyncCapable] / StateSyncService.
class DuckstationSaveStrategy extends SaveStrategy with StateSyncCapable {
  final DirectoryService _directoryService;
  final PlatformInfo _platform;
  final RomGameIds _gameIds;
  final ZstdDecompressor? _zstd;

  DuckstationSaveStrategy(
    this._directoryService,
    AppPreferences prefs, {
    PlatformInfo? platform,
    RomGameIds? gameIds,
    ZstdDecompressor? zstd,
  }) : _platform = platform ?? PlatformInfo.current,
       _zstd = zstd,
       _gameIds = gameIds ?? RomGameIds(prefs);

  @override
  String get strategyId => 'duckstation';

  /// The game's PS1 serial (e.g. "SLES-03508"): RomM's, else read from the
  /// ROM through sigil ([RomGameIds]). Null if neither has it.
  Future<String?> _serial(Game game, String romPath) => GameIdResolver.resolve(
    label: 'DuckStation ${game.name}',
    server: GameIdResolver.discSerial(game, romPath),
    shape: GameIdResolver.ps1ps2Serial,
    local: () => _gameIds.discSerial(romPath, platform: 'psx'),
  );

  /// DuckStation's per-game state naming: `SERIAL_N.sav` or
  /// `SERIAL_resume.sav` (System::GetGameSaveStateFileName). The character
  /// class excludes path separators; `.sav.backup` doesn't match. The global
  /// slots (`savestate_N.sav`) aren't tied to a game and are never matched.
  static final _stateFilePattern = RegExp(r'^([A-Za-z0-9-]+)_(resume|\d{1,2})\.sav$');

  static String _serialKey(String serial) => serial.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static RegExpMatch? _matchState(String fileName) {
    final match = _stateFilePattern.firstMatch(fileName);
    if (match == null || match.group(1)!.toLowerCase() == 'savestate') return null;
    return match;
  }

  @override
  Future<String> stateDirectory(Game game, String romPath) async =>
      p.join(await _getBaseDir(platformSlug: game.platformSlug), 'savestates');

  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) async {
    final serial = await _serial(game, romPath);
    if (serial == null) return null;
    final wanted = _serialKey(serial);
    return (String fileName) {
      final match = _matchState(fileName);
      return match != null && _serialKey(match.group(1)!) == wanted;
    };
  }

  @override
  bool looksLikeValidState(Uint8List bytes) => DuckstationStateFile.hasMagic(bytes);

  @override
  StateSlot slotOf(String fileName) {
    final match = _matchState(fileName);
    if (match == null) return UnknownStateSlot(fileName);
    final slot = match.group(2)!;
    return slot == 'resume' ? const AutoStateSlot() : NumberedStateSlot(int.parse(slot));
  }

  /// DuckStation records only its state format version, not the build that
  /// wrote the state: there is no emulator version to compare.
  @override
  Future<StateFileInfo> describeState(File file) async {
    final base = await super.describeState(file);
    final format = await DuckstationStateFile.readFormatVersion(file);
    return StateFileInfo(savedAt: base.savedAt, formatId: format?.toString());
  }

  @override
  Future<Uint8List?> stateScreenshot(File file) => DuckstationStateFile.readScreenshot(file, zstd: _zstd);

  String _getEmuExe() {
    if (_platform.isWindows) return 'duckstation-qt-x64-ReleaseLTCG.exe';
    if (_platform.isMacOS) return 'DuckStation.app/Contents/MacOS/DuckStation';
    return 'duckstation-qt';
  }

  Future<String> _getBaseDir({String? platformSlug}) async {
    // 1. Check portable mode first (all platforms)
    //
    // DuckStation treats the install as portable when EITHER portable.txt OR
    // settings.ini exists next to the executable (upstream core.cpp):
    //   if (FileExists("portable.txt") || FileExists("settings.ini"))
    //     DataRoot = exe dir
    // Scoop installs and some portable builds only have settings.ini (created
    // on first run), so we must check both or we fall through to the wrong
    // directory and report "no saves" (issue #28).
    final exePath = await _directoryService.findEmulatorExecutable('duckstation', _getEmuExe());
    if (exePath != null) {
      String emulatorDir = File(exePath).parent.path;
      if (_platform.isMacOS && exePath.contains('.app/Contents/MacOS/')) {
        emulatorDir = io.File(exePath).parent.parent.parent.parent.path;
      }
      final portableMarker = File(p.join(emulatorDir, 'portable.txt'));
      final settingsMarker = File(p.join(emulatorDir, 'settings.ini'));
      if (await portableMarker.exists() || await settingsMarker.exists()) {
        debugPrint(
          '[DuckStation] portable mode detected via '
          '${await portableMarker.exists() ? "portable.txt" : "settings.ini"} → $emulatorDir',
        );
        return emulatorDir;
      }
      debugPrint('[DuckStation] exe found at $exePath but no portable.txt/settings.ini — not portable');
    } else {
      debugPrint('[DuckStation] no duckstation exe found via DirectoryService');
    }

    // 2. Dynamic path resolution for macOS/Windows/Linux
    final String resolvedPath;
    if (_platform.isWindows) {
      final localAppData = _platform.environment['LOCALAPPDATA'] ?? '';
      resolvedPath = p.join(localAppData, 'DuckStation');
    } else {
      resolvedPath = await _directoryService.getEmulatorAppSupportDirectory('DuckStation', platformSlug: platformSlug);
    }

    debugPrint('[DuckStation] standard install base candidate: $resolvedPath');
    if (!await io.Directory(resolvedPath).exists()) {
      throw Exception(
        'Save directory not found for DuckStation at $resolvedPath. Please launch DuckStation at least once to generate save data.',
      );
    }
    return resolvedPath;
  }

  // ─── Memory cards ─────────────────────────────────────────────────────────
  //
  // DuckStation names a game's card by its "Memory Card Type" setting
  // (`[MemoryCards] CardNType`, overridable per game in
  // `gamesettings/<SERIAL>.ini`): `<serial>_N.mcd`, `<title>_N.mcd` (the
  // `saveName` in its own gamedb.yaml) or `<ROM file name>_N.mcd`, N being
  // the port. sigil syncs the cards; [sigilCard] tells it the setting in
  // effect and, by title, the name.

  Future<_CardSetup> _cardSetup(Game game, String romPath, {bool needSerial = true}) async {
    final baseDir = await _getBaseDir(platformSlug: game.platformSlug);
    final serial = needSerial ? await _serial(game, romPath) : null;
    final globalIni = await _readIfExists(p.join(baseDir, 'settings.ini'));
    final gameIni = serial == null ? null : await _readIfExists(p.join(baseDir, 'gamesettings', '$serial.ini'));
    final config = DuckstationMemcardConfig.fromIni(globalIni, gameIni);
    final directory = config.directory;
    final memcardsDir = directory == null
        ? p.join(baseDir, 'memcards')
        : (p.isAbsolute(directory) ? directory : p.join(baseDir, directory));
    return _CardSetup(memcardsDir: memcardsDir, config: config, serial: serial);
  }

  static Future<String?> _readIfExists(String path) async {
    try {
      final file = File(path);
      return await file.exists() ? await file.readAsString() : null;
    } catch (e) {
      debugPrint('[DuckStation] cannot read $path: $e');
      return null;
    }
  }

  /// DuckStation's installed `resources` folder (holding gamedb.yaml), or
  /// null when it can't be found (e.g. inside an AppImage).
  Future<String?> _resourcesDir() async {
    final exePath = await _directoryService.findEmulatorExecutable('duckstation', _getEmuExe());
    if (exePath == null) return null;
    final exeDir = File(exePath).parent;
    for (final dir in [
      p.join(exeDir.path, 'resources'),
      if (_platform.isMacOS) p.join(exeDir.parent.path, 'Resources'),
    ]) {
      if (await File(p.join(dir, 'gamedb.yaml')).exists()) return dir;
    }
    return null;
  }

  /// The exact name (without `_N.mcd`) DuckStation gives [game]'s card of
  /// [type], or null when it can't be known: the serial couldn't be read,
  /// or (by title) the game database doesn't know the game.
  Future<String?> _cardName(_CardSetup setup, DuckstationCardType type, Game game, String romPath, int port) async {
    switch (type) {
      case DuckstationCardType.perGameSerial:
        return setup.serial;
      case DuckstationCardType.perGameFileTitle:
        final title = await FileSystemEntity.isDirectory(romPath)
            ? getRomStem(game)
            : p.basenameWithoutExtension(romPath);
        return duckstationSafeFileName(title, _platform);
      case DuckstationCardType.perGameTitle:
        final serial = setup.serial;
        final resources = serial == null ? null : await _resourcesDir();
        if (serial == null || resources == null) return null;
        final discTitle = await DuckstationGameDb.saveTitle(resources, serial, usePlaylistTitle: false);
        final setTitle = setup.config.usePlaylistTitle ? await DuckstationGameDb.discSetTitle(resources, serial) : null;
        if (setTitle == null || discTitle == null) {
          final title = setTitle ?? discTitle;
          return title == null ? null : duckstationSafeFileName(title, _platform);
        }
        // A multi-disc game shares the disc set's card, but, as DuckStation
        // does, a card already made under this disc's own title wins.
        final discName = duckstationSafeFileName(discTitle, _platform);
        if (await File(p.join(setup.memcardsDir, '${discName}_$port.mcd')).exists()) return discName;
        return duckstationSafeFileName(setTitle, _platform);
      default:
        return null;
    }
  }

  /// Gargosy (sigil): where DuckStation keeps [game]'s cards and how it
  /// names them, for sigil's `duckstation` layout: [root] holds `memcards/`
  /// (null when the cards are in a folder of another name), [options] the
  /// card types in effect (the per-game setting wins), and [stem] the name
  /// sigil should take as the content's (`<stem>_1.mcd`) when DuckStation
  /// names port 1's card by the game database's title; null otherwise (sigil
  /// then names it from the serial or the ROM file, as DuckStation does).
  Future<({String? root, String? stem, Map<String, String> options})> sigilCard(Game game, String romPath) async {
    final setup = await _cardSetup(game, romPath);
    final type = setup.config.typeOf(1);
    String? stem;
    if (type == DuckstationCardType.perGameTitle) {
      stem = await _cardName(setup, type, game, romPath, 1);
      if (stem == null) {
        final found = await _cardByTitleWords(setup.memcardsDir, game, 1);
        if (found != null) stem = p.basename(found.path).replaceFirst(RegExp(r'_1\.mcd$', caseSensitive: false), '');
      }
    }
    return (
      root: p.basename(setup.memcardsDir).toLowerCase() == 'memcards' ? p.dirname(setup.memcardsDir) : null,
      stem: stem,
      options: {'Card1Type': type.iniValue, 'Card2Type': setup.config.typeOf(2).iniValue},
    );
  }

  /// Fallback when the card title isn't known: the newest card for [port]
  /// whose name contains every word (3+ letters) of the ROM name without its
  /// tags. Word matching avoids "final fantasy vii" matching "... viii";
  /// multi-disc `.m3u` names like "Final Fantasy VII (USA).m3u" match
  /// "Final Fantasy VII_1.mcd" (issue #62).
  Future<File?> _cardByTitleWords(String memcardsDir, Game game, int port) async {
    final dir = Directory(memcardsDir);
    if (!await dir.exists()) return null;
    final stemTokens = _words(normalizeSaveMatchName(getRomStem(game))).where((w) => w.length >= 3).toList();
    if (stemTokens.isEmpty) return null;
    final suffix = '_$port.mcd';
    File? best;
    DateTime? bestModified;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final base = p.basename(entity.path);
      final lower = base.toLowerCase();
      if (!lower.endsWith(suffix) || lower.startsWith('shared_card_')) continue;
      final cardTokens = _words(normalizeSaveMatchName(base.substring(0, base.length - suffix.length)));
      if (!stemTokens.every(cardTokens.contains)) continue;
      final modified = await entity.lastModified();
      if (best == null || modified.isAfter(bestModified!)) {
        best = entity;
        bestModified = modified;
      }
    }
    return best;
  }

  static List<String> _words(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ' ').split(' ').where((w) => w.isNotEmpty).toList();

  /// A pull into a card shared by all games rewrites that card: it must be
  /// done before DuckStation opens it.
  @override
  Future<bool> pullMustFinishBeforeLaunch(Game game, String romPath) async {
    try {
      final config = (await _cardSetup(game, romPath)).config;
      return config.portsOfType((t) => t == DuckstationCardType.shared).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Gargosy (#57): DuckStation's saves (the memory cards) go through sigil,
  // which covers every PS1 game (SigilSaveStrategy, with [sigilCard] for
  // where and under what name); this strategy is for states and the card
  // setup sigil reads.
  @override
  Future<String?> getSaveDir(Game game, String romPath) async => null;

  @override
  Future<List<File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async => const [];

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async => false;
}

/// What [DuckstationSaveStrategy] needs to name a game's memory cards.
class _CardSetup {
  _CardSetup({required this.memcardsDir, required this.config, required this.serial});
  final String memcardsDir;
  final DuckstationMemcardConfig config;
  final String? serial;
}
