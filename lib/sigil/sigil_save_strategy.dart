import 'dart:io' as io;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/romm/game_id_resolver.dart';
import '../core/romm/romm_models.dart';
import '../core/save/save_state_info.dart';
import '../core/save/save_strategy.dart';
import '../core/save/state_sync_capable.dart';
import '../core/save/strategies/retroarch_save_strategy.dart';
import '../core/storage/ini_file.dart';
import '../emulators/pcsx2_folder_card.dart';
import 'rom_game_ids.dart';
import 'sigil_engine.dart';
import 'sigil_state_store.dart';
import 'sigil_sync.dart';

/// An emulator whose saves sigil collects and restores in Gargosy.
class SigilEmulator {
  const SigilEmulator({
    required this.id,
    required this.layout,
    required this.saveRoot,
    required this.platforms,
    this.options = _none,
    this.beforeRestore,
    this.layoutFor,
    this.saveRootFor,
    this.optionsFor,
  });

  final String id;

  /// sigil's layout id.
  final String layout;

  /// The save root inside the profile's folder for the emulator.
  final String saveRoot;

  /// The layout for [game] when it depends on the game (RetroArch: the
  /// core it runs with, from [base]); null means sigil doesn't sync it and
  /// [base] keeps it. Unset: [layout] for every game.
  final String? Function(Game game, SaveStrategy? base)? layoutFor;

  /// The save root for a game's [layout] and options, when it isn't
  /// [saveRoot] (RetroArch's LRPS2 keeps its shared cards in
  /// `system\pcsx2\memcards`, a game's own card in `saves\`).
  final String Function(String layout, Map<String, String> options)? saveRootFor;

  /// The options for one game, when they depend on it (RetroArch: the
  /// core's and the game's own `.opt` files over the global ones). Unset:
  /// [options].
  final Map<String, String> Function(String emulatorDir, Game game, String romPath, SaveStrategy? base)? optionsFor;

  /// RomM's platform slugs it syncs → sigil's.
  final Map<String, String> platforms;

  /// The emulator's settings that change save file names, from its config.
  final Map<String, String> Function(String emulatorDir) options;

  /// Readies the save root for a restore (PCSX2: the card it writes to).
  final void Function(String saveRoot, Map<String, String> options)? beforeRestore;

  static Map<String, String> _none(String _) => const {};
}

Map<String, String> _ini(String file, String section, List<String> keys) {
  final f = io.File(file);
  if (!f.existsSync()) return const {};
  try {
    final ini = IniFile(f.readAsStringSync());
    return {
      for (final k in keys)
        if (ini.get(section, k) case final v? when v.trim().isNotEmpty) k: v.trim(),
    };
  } catch (_) {
    return const {};
  }
}

/// The emulators sigil syncs here (spec: stage 2), as sigil's docs/platforms
/// list them.
final sigilEmulators = <String, SigilEmulator>{
  'pcsx2': SigilEmulator(
    id: 'pcsx2',
    layout: 'pcsx2_standalone',
    saveRoot: 'PCSX2',
    platforms: const {'ps2': 'ps2', 'playstation-2': 'ps2', 'playstation2': 'ps2'},
    options: (dir) =>
        _ini(p.join(dir, 'PCSX2', 'inis', 'PCSX2.ini'), 'MemoryCards', const ['Slot1_Filename', 'Slot2_Filename']),
    // With no card at all sigil would write a file card and fail reading it
    // back; Gargosy's PCSX2 cards are folder cards, as a new profile's is.
    beforeRestore: (root, options) {
      final card = p.join(root, 'memcards', options['Slot1_Filename'] ?? 'Mcd001.ps2');
      if (io.FileSystemEntity.typeSync(card) == io.FileSystemEntityType.notFound) ensurePcsx2FolderCard(card);
    },
  ),
  'duckstation': SigilEmulator(
    id: 'duckstation',
    layout: 'duckstation',
    saveRoot: '.',
    platforms: const {'psx': 'psx', 'ps': 'psx', 'ps1': 'psx', 'playstation': 'psx'},
    options: (dir) => _ini(p.join(dir, 'settings.ini'), 'MemoryCards', const ['Card1Type', 'Card2Type']),
  ),
  'dolphin': SigilEmulator(
    id: 'dolphin',
    layout: 'dolphin_standalone',
    saveRoot: '.',
    platforms: const {'ngc': 'gamecube', 'gc': 'gamecube', 'gamecube': 'gamecube'},
    options: (dir) => _ini(p.join(dir, 'Config', 'Dolphin.ini'), 'Core', const ['SlotA', 'MemoryCardSize']),
  ),
  'ppsspp': const SigilEmulator(
    id: 'ppsspp',
    layout: 'ppsspp_standalone',
    saveRoot: '.',
    platforms: {'psp': 'psp', 'playstation-portable': 'psp'},
  ),
  'flycast': SigilEmulator(
    id: 'flycast',
    layout: 'flycast_standalone',
    saveRoot: 'vmu',
    platforms: const {'dc': 'dreamcast', 'dreamcast': 'dreamcast'},
    options: (dir) => _ini(p.join(dir, 'emu.cfg'), 'config', const ['PerGameVmu']),
  ),
  // RetroArch (issue #7): the layout is the game's core without `_libretro`
  // (sigil's rows are named so; a core with no row takes the libretro
  // default, `{stem}.srm`). Only the systems sigil collects and restores
  // for, and that were checked on real files (test/unit/sigil_retroarch_test):
  // SNES, GBA, Genesis, NES, NDS and arcade are refused by sigil's sync and
  // stay with RetroArchSaveStrategy.
  'retroarch': SigilEmulator(
    id: 'retroarch',
    layout: '',
    saveRoot: 'saves',
    platforms: const {
      'psx': 'psx', 'ps': 'psx', 'ps1': 'psx', 'playstation': 'psx',
      'ps2': 'ps2', 'playstation-2': 'ps2', 'playstation2': 'ps2',
      'n64': 'n64', 'nintendo-64': 'n64',
      'gb': 'gb', 'game-boy': 'gb', 'gbc': 'gbc', 'game-boy-color': 'gbc',
    },
    layoutFor: (game, base) => base is RetroArchSaveStrategy ? base.coreIdFor(game) : null,
    // sigil's docs: LRPS2's shared cards are in <system>\pcsx2\memcards;
    // with Shared Memory Cards off, a game's own card is in the save folder.
    saveRootFor: (layout, options) => layout == 'pcsx2' && options['pcsx2_shared_memory_cards'] != 'disabled'
        ? p.join('system', 'pcsx2', 'memcards')
        : 'saves',
    optionsFor: (dir, game, romPath, base) =>
        retroArchCoreOptions(dir, core: base is RetroArchSaveStrategy ? base.coreFolderFor(game) : null, romPath: romPath),
  ),
  'mgba': const SigilEmulator(
    id: 'mgba',
    layout: 'mgba_standalone',
    saveRoot: 'saves',
    platforms: {'gb': 'gb', 'game-boy': 'gb', 'gbc': 'gbc', 'game-boy-color': 'gbc'},
  ),
};

/// RetroArch's core options for a game, as RetroArch reads them: the
/// global `retroarch-core-options.cfg` (in `config\` and beside
/// retroarch.cfg), then the core's own `config\<core>\<core>.opt` (where
/// they go when global core options are off, the default), then the
/// content folder's and the game's `.opt`, each over the one before
/// (`key = "value"` lines). sigil looks only at the keys its layout row
/// names (`pcsx2_shared_memory_cards`, `pcsx_rearmed_memcard1`, …).
Map<String, String> retroArchCoreOptions(String emulatorDir, {String? core, String? romPath}) {
  final files = [
    p.join(emulatorDir, 'retroarch-core-options.cfg'),
    p.join(emulatorDir, 'config', 'retroarch-core-options.cfg'),
    if (core != null) ...[
      p.join(emulatorDir, 'config', core, '$core.opt'),
      if (romPath != null) p.join(emulatorDir, 'config', core, '${p.basename(p.dirname(romPath))}.opt'),
      if (romPath != null) p.join(emulatorDir, 'config', core, '${p.basenameWithoutExtension(romPath)}.opt'),
    ],
  ];
  final line = RegExp(r'^\s*([A-Za-z0-9_.-]+)\s*=\s*"([^"]*)"\s*$');
  final out = <String, String>{};
  for (final path in files) {
    final f = io.File(path);
    if (!f.existsSync()) continue;
    try {
      for (final l in f.readAsLinesSync()) {
        if (line.firstMatch(l) case final m?) out[m[1]!] = m[2]!;
      }
    } catch (_) {
      // An unreadable file: the ones before it stand.
    }
  }
  return out;
}

typedef SigilCollectFn = Future<SigilCollected> Function(SigilSyncCall call);
typedef SigilRestoreFn = Future<SigilRestored> Function(SigilSyncCall call, Uint8List unit);
typedef SigilIdentifyFn = Future<SigilId?> Function(String path, {String? platform});

/// Where an emulator keeps a game's saves and how it names them, when the
/// emulator's own settings decide that (DuckStation: [root] holding
/// `memcards/`, the card's name [stem], the card types as [options]).
typedef SigilContentFn = Future<({String? root, String? stem, Map<String, String> options})> Function(
  Game game,
  String romPath,
);

/// An emulator's saves through sigil (spec: stage 2): collect gives one
/// unit file for the engine to upload to `autosave`, a download is restored
/// as sigil's unit, and sigil's state is stored only after an upload went
/// through. Games on platforms sigil doesn't sync for the emulator (GBA in
/// mGBA, Wii in Dolphin) and everything that isn't saves (states, the save
/// folder) stay with the emulator's old strategy, [base].
class SigilSaveStrategy extends SaveStrategy {
  SigilSaveStrategy._(
    this.emulator, {
    required this.base,
    required this.emulatorDir,
    required this.states,
    required this.unitsDir,
    SigilCollectFn? collect,
    SigilRestoreFn? restore,
    SigilIdentifyFn? identify,
    this.content,
  }) : _collect = collect ?? SigilEngine.collect,
       _restore = restore ?? SigilEngine.restore,
       _identify = identify ?? SigilEngine.identify;

  /// sigil's strategy for [emulatorId], wrapping [base]; null when sigil
  /// doesn't sync that emulator here.
  static SigilSaveStrategy? forEmulator(
    String emulatorId, {
    required SaveStrategy? base,
    required String Function() emulatorDir,
    required SigilStateStore states,
    required String unitsDir,
    SigilCollectFn? collect,
    SigilRestoreFn? restore,
    SigilIdentifyFn? identify,
    SigilContentFn? content,
  }) {
    final emulator = sigilEmulators[emulatorId];
    if (emulator == null) return null;
    if (base is StateSyncCapable) {
      return _SigilStateSaveStrategy(
        emulator,
        base: base,
        emulatorDir: emulatorDir,
        states: states,
        unitsDir: unitsDir,
        collect: collect,
        restore: restore,
        identify: identify,
        content: content,
      );
    }
    return SigilSaveStrategy._(
      emulator,
      base: base,
      emulatorDir: emulatorDir,
      states: states,
      unitsDir: unitsDir,
      collect: collect,
      restore: restore,
      identify: identify,
      content: content,
    );
  }

  final SigilEmulator emulator;
  final SaveStrategy? base;
  final SigilStateStore states;
  final String unitsDir;

  /// The profile's folder for the emulator.
  final String Function() emulatorDir;
  final SigilCollectFn _collect;
  final SigilRestoreFn _restore;
  final SigilIdentifyFn _identify;

  /// The emulator's own say on where and under what name the saves are.
  final SigilContentFn? content;

  /// The state of the last collect per game, committed in [afterUpload].
  final _pending = <String, Uint8List>{};

  String? _sigilPlatform(Game game) => emulator.platforms[game.platformSlug?.toLowerCase()];

  /// sigil's layout for [game]: the emulator's, or (RetroArch) its core's.
  String? _layout(Game game) {
    final of = emulator.layoutFor;
    if (of == null) return emulator.layout;
    final layout = of(game, base);
    return layout == null || layout.isEmpty ? null : layout;
  }

  bool _covers(Game game) => _sigilPlatform(game) != null && _layout(game) != null;

  Map<String, String> _options(Game game, String romPath) =>
      emulator.optionsFor?.call(emulatorDir(), game, romPath, base) ?? emulator.options(emulatorDir());

  String _root(Game game, String romPath) {
    final layout = _layout(game);
    final rel = layout == null
        ? emulator.saveRoot
        : (emulator.saveRootFor?.call(layout, _options(game, romPath)) ?? emulator.saveRoot);
    return p.normalize(p.join(emulatorDir(), rel));
  }

  /// A collected state waits for its upload under the game and its layout:
  /// another core's collect (the play screen lists every core) never
  /// replaces it.
  String _pendingKey(Game game) => '${game.id}|${_layout(game)}';

  @override
  SaveStrategy? get wrapped => base;

  @override
  String get strategyId => emulator.id;

  @override
  bool get supportsSaveSync => true;

  /// The old strategy's (Wii in Dolphin zips as before); a sigil unit is
  /// one file, which goes up as it is either way.
  @override
  bool get shouldZip => base?.shouldZip ?? false;

  @override
  String uploadSlotFor(Game game) => _covers(game) ? 'autosave' : (base?.uploadSlotFor(game) ?? 'gargosy');

  @override
  bool restoresUnitsItselfFor(Game game) => _covers(game) || (base?.restoresUnitsItselfFor(game) ?? false);

  @override
  Future<void> afterUpload(Game game, String romPath) async {
    if (!_covers(game)) return base?.afterUpload(game, romPath);
    final state = _pending.remove(_pendingKey(game));
    if (state == null) return;
    states.write(emulator.id, game.id, state);
    // The unit held the claimed saves: sigil's state knows their owner now.
    states.setClaims(emulator.id, game.id, const []);
  }

  @override
  Future<List<String>> unclaimedSavesFor(Game game, String romPath) async {
    if (!_covers(game)) return await base?.unclaimedSavesFor(game, romPath) ?? const [];
    try {
      final call = await _call(game, romPath, state: states.read(emulator.id, game.id), claimed: true);
      return (await _collect(call)).unowned;
    } on SigilSyncError catch (e) {
      debugPrint('[Sigil] ${emulator.id} ${game.name}: unclaimed saves not read ($e)');
      return const [];
    }
  }

  @override
  Future<void> claimSave(Game game, String romPath, String name) async {
    if (!_covers(game)) return base?.claimSave(game, romPath, name);
    final claims = states.claims(emulator.id, game.id);
    if (!claims.contains(name)) states.setClaims(emulator.id, game.id, [...claims, name]);
    debugPrint('[Sigil] ${emulator.id} ${game.name}: claimed $name');
  }

  @override
  Future<String?> saveSyncBlockedReason(Game game, String romPath) async {
    if (!_covers(game)) return base?.saveSyncBlockedReason(game, romPath);
    // LRPS2 on shared cards without a serial: sigil couldn't tell this
    // game's saves from the others', so the old strategy's reason stands.
    if (_layout(game) == 'pcsx2') return base?.saveSyncBlockedReason(game, romPath);
    return null;
  }

  /// Restoring touches a card other games may share: it finishes before launch.
  @override
  Future<bool> pullMustFinishBeforeLaunch(Game game, String romPath) async =>
      await base?.pullMustFinishBeforeLaunch(game, romPath) ?? false;

  @override
  Future<String?> getSaveDir(Game game, String romPath) async =>
      _covers(game) ? _root(game, romPath) : base?.getSaveDir(game, romPath);

  @override
  Future<List<io.File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async {
    if (!_covers(game)) return base?.getSaveFiles(game, romPath, sessionStart: sessionStart, syncMode: syncMode) ?? [];
    final SigilCollected collected;
    SigilSyncCall? call;
    try {
      call = await _call(game, romPath, state: states.read(emulator.id, game.id), claimed: true);
      collected = await _collect(call);
    } on SigilSyncError catch (e) {
      // A card sigil can't read is said, not a silent "nothing to upload".
      throw SaveSyncNotPossibleException(_explain(e, p.basename(romPath)));
    }
    final data = collected.data;
    if (data == null) return [];
    if (collected.state != null) _pending[_pendingKey(game)] = collected.state!;
    final dir = io.Directory(p.join(unitsDir, emulator.id, game.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final unit = io.File(p.join(dir.path, p.basename(collected.artifact)))..writeAsBytesSync(data, flush: true);
    // The save's own time, for the catalog and the play screen's "newest".
    if (_savedAt(collected, call) case final saved?) unit.setLastModifiedSync(saved);
    debugPrint(
      '[Sigil] ${emulator.id} ${game.name}: unit ${collected.artifact} (${data.length} bytes, '
      '${collected.changed ? 'changed' : 'unchanged'})',
    );
    return [unit];
  }

  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async {
    if (!_covers(game)) return base?.restoreSave(game, destPath, data, filename) ?? false;
    try {
      // Only a restore the user chose may replace a save changed on this PC
      // since the last sync (the play screen backs it up first).
      final call = await _call(
        game,
        destPath,
        state: states.read(emulator.id, game.id),
        overwriteLocal: SaveStrategy.isChosenRestore,
      );
      emulator.beforeRestore?.call(call.saveRoot, call.options);
      final restored = await _restore(call, data);
      if (restored.state != null) states.write(emulator.id, game.id, restored.state!);
      return true;
    } on SigilSyncError catch (e) {
      if (e.code == -9) {
        throw SaveSyncNotPossibleException(
          "Your save on this PC changed since it last synced, so RomM's save wasn't put in place. "
          "Pick RomM's save on the play screen to use it instead.",
        );
      }
      throw SaveSyncNotPossibleException(_explain(e, filename));
    }
  }

  /// A backup is a zip of the unit file: each goes back through sigil.
  @override
  Future<bool> restoreBackup(Game game, String romPath, Uint8List zipBytes, String zipName) =>
      SaveStrategy.chosenRestore(() => _restoreBackup(game, romPath, zipBytes, zipName));

  Future<bool> _restoreBackup(Game game, String romPath, Uint8List zipBytes, String zipName) async {
    if (!_covers(game)) return base?.restoreBackup(game, romPath, zipBytes, zipName) ?? false;
    final entries = ZipDecoder().decodeBytes(zipBytes).files.where((e) => e.isFile).toList();
    // A backup from before sigil (a zip of save folders, several files) is
    // one of the shapes sigil's restore reads: it goes back whole.
    if (entries.length != 1 || entries.single.name.contains('/')) {
      return restoreSave(game, romPath, zipBytes, zipName);
    }
    var ok = true;
    for (final entry in entries) {
      if (!entry.isFile) continue;
      ok =
          await restoreSave(game, romPath, Uint8List.fromList(entry.content as List<int>), p.basename(entry.name)) &&
          ok;
    }
    return ok;
  }

  /// [claimed]: a collect, which takes the player's claims (#56) along.
  Future<SigilSyncCall> _call(Game game, String romPath,
      {Uint8List? state, bool overwriteLocal = false, bool claimed = false}) async {
    final platform = _sigilPlatform(game)!;
    final layout = _layout(game)!;
    final ids = await _ids(game, romPath, platform);
    final hint = await content?.call(game, romPath);
    final stem = hint?.stem;
    return SigilSyncCall(
      layout: layout,
      platform: platform,
      // sigil names a card from the content's file name: the emulator's own
      // card name, as sigil's README suggests (`<name>.cue`), when it has one.
      contentPath: stem == null ? romPath : p.join(p.dirname(romPath), '$stem.cue'),
      saveRoot: hint?.root ?? _root(game, romPath),
      gameIds: ids.gameIds,
      titleId: ids.titleId,
      rawSerial: ids.rawSerial,
      saveId: ids.saveId,
      usage: ids.usage,
      options: {..._options(game, romPath), ...?hint?.options},
      state: state,
      overwriteLocal: overwriteLocal,
      claimed: claimed ? states.claims(emulator.id, game.id) : const [],
    );
  }

  /// The game's ids: RomM's (`title_id`, `save_target`, its layout), else
  /// read from the ROM by sigil. PS1/PS2 serials in their save-folder form.
  Future<({String? titleId, String? rawSerial, String? saveId, int? usage, List<String> gameIds})> _ids(
    Game game,
    String romPath,
    String platform,
  ) async {
    if (platform == 'gb' || platform == 'gbc' || platform == 'n64') {
      return (titleId: null, rawSerial: null, saveId: null, usage: null, gameIds: const <String>[]);
    }
    final disc = platform == 'ps2' || platform == 'psx';
    // RomM reads the first disc (a set's saves are under its code); a later
    // disc's own id is read from the ROM.
    final rommId = disc ? GameIdResolver.clean(game.titleId) : null;
    final setId = rommId == null ? null : RomGameIds.normalizeSerial(rommId);
    String? titleId = disc
        ? GameIdResolver.discSerial(game, romPath)
        : platform == 'psp'
        ? GameIdResolver.discFolderId('sigil ${game.name}', game)
        : GameIdResolver.clean(game.titleId);
    String? saveId = GameIdResolver.clean(game.saveTarget);
    int? usage = game.saveTargetLayout?.index;
    String? rawSerial = platform == 'gamecube' ? saveId : null;
    if (platform == 'psp' && titleId != null) {
      saveId ??= titleId;
      usage ??= 1; // PSP saves: SAVEDATA/<id>* folders
    }
    if (titleId == null) {
      final read = await _identify(romPath, platform: platform);
      if (read != null) {
        titleId = disc ? RomGameIds.normalizeSerial(read.titleId) : read.titleId;
        rawSerial = read.rawSerial;
        // RomM's save name is the set's; a later disc keeps it.
        saveId = saveId ?? (read.saveId.isEmpty ? null : read.saveId);
        usage = usage ?? read.usage;
      }
    }
    if (titleId == null) {
      debugPrint('[Sigil] ${emulator.id} ${game.name}: no game id from RomM or the ROM');
      return (titleId: null, rawSerial: null, saveId: null, usage: null, gameIds: const <String>[]);
    }
    // Every id the saves may carry: this disc's and the set's (sigil.h).
    final gameIds = {titleId, ?setId}.toList();
    return (titleId: titleId, rawSerial: rawSerial, saveId: saveId, usage: usage, gameIds: gameIds);
  }

  /// When the game's save was written: the newest file sigil read inside
  /// the game's own save folders (their names hold its save or title id),
  /// else the newest of everything it read (a card other games share).
  static DateTime? _savedAt(SigilCollected c, SigilSyncCall? call) {
    final ids = [call?.saveId, call?.titleId, call?.rawSerial].whereType<String>().map((i) => i.toUpperCase());
    DateTime? own;
    for (final e in c.reads.entries) {
      final path = e.key.toUpperCase();
      if (ids.any(path.contains) && (own == null || e.value.isAfter(own))) own = e.value;
    }
    return own ?? c.newestRead;
  }

  static String _explain(SigilSyncError e, String filename) {
    final what = e.problem.isEmpty ? '' : ' (${e.problem.trim()})';
    return switch (e.code) {
      -11 =>
        "$filename doesn't fit on the memory card$what${e.blocksShort > 0 ? ': ${e.blocksShort} blocks short' : ''}.",
      -13 => 'A save file is damaged$what; it was left as it is.',
      -5 || -4 => "sigil can't read $filename as a save of this game$what.",
      -16 => 'More than one memory card could be the one the emulator uses$what.',
      -10 => 'A save with that name is already there$what.',
      -15 => "The emulator's settings keep no file for part of this save$what.",
      _ => "$filename couldn't be put in place: ${e.message}$what.",
    };
  }
}

/// [SigilSaveStrategy] for an emulator whose old strategy also syncs save
/// states: those stay with it.
class _SigilStateSaveStrategy extends SigilSaveStrategy with StateSyncCapable {
  _SigilStateSaveStrategy(
    super.emulator, {
    required super.base,
    required super.emulatorDir,
    required super.states,
    required super.unitsDir,
    super.collect,
    super.restore,
    super.identify,
    super.content,
  }) : super._();

  StateSyncCapable get _states => base! as StateSyncCapable;

  @override
  Future<String> stateDirectory(Game game, String romPath) => _states.stateDirectory(game, romPath);

  @override
  Future<bool Function(String fileName)?> stateFileMatcher(Game game, String romPath) =>
      _states.stateFileMatcher(game, romPath);

  @override
  bool looksLikeValidState(Uint8List bytes) => _states.looksLikeValidState(bytes);

  @override
  StateSlot slotOf(String fileName) => _states.slotOf(fileName);

  @override
  Future<StateFileInfo> describeState(io.File file) => _states.describeState(file);

  @override
  Future<Uint8List?> stateScreenshot(io.File file) => _states.stateScreenshot(file);
}
