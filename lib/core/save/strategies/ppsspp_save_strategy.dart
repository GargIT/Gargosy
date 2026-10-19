// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy: StateSyncCapable (#59): states in PSP\PPSSPP_STATE, the game by
// its disc id (RomM's, else sigil's), Resume with `--state=`.
import 'dart:io' as io;
import 'dart:io' show File;

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

/// PPSSPP's save states (PSP); its saves go through sigil (#57).
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
      final exePath = await _directoryService.findEmulatorExecutable('ppsspp', _getEmuExe());
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

  // Gargosy (#57): PPSSPP's saves (PSP\SAVEDATA) go through sigil, which
  // answers for every PSP game (SigilSaveStrategy); this strategy is for states.
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
        final id = (await _identify(
          romPath,
          platform: 'psp',
        ))?.titleId.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
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
}
