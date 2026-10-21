import '../emulators/fullscreen.dart';
import '../core/save/catalog/save_entry.dart';
import '../profiles/profile_providers.dart';
import '../profiles/path_guard.dart';
import '../profiles/json_file.dart';
import '../core/emulator/strategies/retroarch_strategy.dart';

import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';

import 'dart:io' as io;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emulator/emulator_strategy.dart';
import '../core/emulator/game_launch_service.dart';
import '../core/emulator/retroarch_core_list.dart';
import '../core/romm/romm_models.dart';
import '../core/save/catalog/play_preparer.dart';
import '../core/save/catalog/play_request.dart';
import '../core/save/catalog/save_catalog_sources.dart';
import '../core/save/catalog/save_maker.dart';
import '../core/save/resume_service.dart';
import '../emulators/emulator_layout.dart';
import '../emulators/emulator_library.dart';
import '../emulators/profile_launch_config.dart';
import '../providers/download_providers.dart';
import '../providers/engine_providers.dart';
import '../providers/romm_providers.dart';
import '../library/rom_preparer.dart';
import '../ui/play/emulator_choices.dart';
import 'play_menu.dart';
import 'pre_launch_pull.dart';

/// What a finished session says ("Save synced", …).
class PlayResult {
  const PlayResult(this.message, {this.synced = false});
  final String message;

  /// RomM has this PC's save now (it took it, or it already had it).
  final bool synced;
}

/// A running game; [finished] completes once it exits and its saves synced.
class PlaySession {
  const PlaySession(this.finished);
  final Future<PlayResult> finished;
}

/// What the pre-launch state pull did: the states it brought down or found
/// up to date, and those that differ on RomM (left alone; this PC's copy is
/// used). Both null when no pull ran.
class StatePull {
  const StatePull({this.current, this.conflicted});
  final Set<String>? current;
  final Set<String>? conflicted;
}

/// The steps of playing a game, as Freegosy's launch flow does them. The real
/// one is [GargosyPlayEngine]; tests use a fake.
abstract class PlayEngine {
  /// What the play screen offers for [game]; null without a profile.
  Future<PlayMenu?> menuFor(Game game);

  /// The emulator [game] plays in: [emulatorId] when given, else the one
  /// remembered for it, else the platform's.
  Future<EmulatorStrategy?> emulatorFor(Game game, {String? emulatorId});
  Future<bool> isInstalled(EmulatorStrategy strategy);

  /// The ROM to start, or null when the game isn't downloaded.
  Future<String?> romPathFor(Game game);

  /// [romPath] made ready for [strategy], once (`RomPreparer`): a zip it
  /// can't open is unpacked, an Xbox disc made an XISO for xemu. Returns
  /// the ROM to start; throws with the reason when it can't be readied.
  Future<String> readyRom(Game game, String romPath, EmulatorStrategy strategy, {void Function(String)? onProgress});

  /// Backs up this PC's save, then puts the profile's RomM save in place.
  /// The states [game] can be resumed from: this PC's first, then merged
  /// with RomM's.
  Stream<List<ResumeEntry>> statesFor(Game game);

  /// Brings the profile's states down from RomM before launch (when state
  /// sync is on for the emulator and RomM is reachable); [priority] first.
  /// Never throws.
  Future<StatePull> pullStates(
    Game game,
    String romPath,
    EmulatorStrategy strategy, {
    String? priority,
    String? coreOverride,
    void Function(String)? onProblem,
  });

  /// Whether [entry] can be loaded now (after [pull]).
  Future<ResumeCheck> checkResume(ResumeEntry entry, Game game, String romPath, StatePull pull);

  /// Stores or forgets [game]'s emulator as [request] says.
  Future<void> remember(Game game, PlayRequest request);

  /// Puts the save in place before launch. With [request], the save the
  /// play screen chose (null: the emulator's own save on this PC), and a
  /// failure stops the launch (SaveChoiceException). Without, this PC's
  /// save is backed up and the profile's RomM save pulled; that never
  /// throws for a save problem: [onProblem] is told instead.
  Future<void> prepare(
    Game game,
    String romPath,
    EmulatorStrategy strategy, {
    PlayRequest? request,
    String? coreOverride,
    void Function(String)? onProblem,
  });
  Future<PlaySession> launch(
    Game game,
    String romPath,
    EmulatorStrategy strategy, {
    String? coreOverride,
    String? loadStatePath,
  });

  /// Opens the emulator at [exePath] on the profile's data with no game, for
  /// its own settings (controllers). Completes when it has started;
  /// [onExit] runs when it exits.
  Future<void> openEmulator(String emulatorId, String exePath, {required void Function() onExit});

  /// Puts a RomM save or a backup on this PC for [target] without launching
  /// (backs up the current save first). Throws SaveChoiceException.
  Future<void> restore(Game game, SaveEntry save, SaveMaker target);

  /// Deletes a RomM save on RomM, or a backup from this PC.
  Future<void> deleteSave(Game game, SaveEntry save);

  /// Uploads this PC's save of [who] to RomM; true when RomM took it.
  Future<bool> upload(Game game, SaveMaker who);

  /// A backup of this PC's save of [who], now.
  Future<void> backUpNow(Game game, SaveMaker who);

  /// The saves on a volume other games share (Flycast's VMU) that no game
  /// owns, for [who] (#56); empty when none or the game isn't on this PC.
  Future<List<String>> unclaimedSaves(Game game, SaveMaker who);

  /// [name] becomes [game]'s save and goes up to RomM with it; true when
  /// RomM took it.
  Future<bool> claimSave(Game game, SaveMaker who, String name);

  /// State sync is on for [game]'s emulator.
  bool stateSyncAvailable(Game game);

  /// Brings states down from RomM and up to it; says what moved.
  Future<String> syncStatesNow(Game game);

  /// The player's own RomM fields for [game]; true when RomM took them.
  Future<bool> setRommUser(
    Game game, {
    String? status,
    int? rating,
    int? completion,
    bool? backlogged,
    bool? nowPlaying,
  });

  /// Downloads the RetroArch core [missing] names into the RetroArch install
  /// (shared by every profile). Throws when it can't.
  Future<void> installCore(EmulatorStrategy strategy, MissingRetroArchCoreException missing);

  /// The play screen's Full screen switch, for every game in [emulatorId].
  Future<void> setFullscreen(String emulatorId, bool on);
}

/// [PlayEngine] on the active profile's copy of Freegosy's engine.
class GargosyPlayEngine implements PlayEngine {
  GargosyPlayEngine(this._ref);

  final Ref _ref;

  Future<GameLaunchService> _launch() async {
    final s = await _ref.read(gameLaunchServiceProvider.future);
    if (s == null) throw StateError('No profile is active');
    return s;
  }

  @override
  Future<PlayMenu?> menuFor(Game game) async {
    final registry = _ref.read(strategyRegistryProvider);
    final sync = _ref.read(saveSyncServiceProvider);
    final repo = await _ref.read(backupRepositoryProvider.future);
    final prefs = _ref.read(profilePrefsProvider);
    if (registry == null || sync == null || repo == null) return null;
    final installed = {
      for (final e in await _ref.read(emulatorsProvider.future)) e.id: e.supported && e.installedExe != null,
    };
    final choices = EmulatorChoices.of(registry, installed, game);
    final romPath = await romPathFor(game) ?? _ref.read(romFilesProvider).pathFor(game);
    final catalog = await loadSaveCatalog(
      game,
      romPath,
      LiveSaveCatalogSources(
        sync: sync,
        registry: registry,
        backupRepository: repo,
        rommService: _ref.read(rommServiceProvider),
        installed: installed,
        rommUserId: _ref.read(activeProfileProvider)?.profile.rommUserId,
      ),
    );
    return PlayMenu(
      emulators: [
        for (final s in choices.emulators)
          EmulatorOption(
            choices.makerFor(s.emulatorId),
            s.emulatorId == 'retroarch' ? s.name : choices.nameOf(choices.makerFor(s.emulatorId)),
            cores: s.emulatorId == 'retroarch' ? getCoresForSlug(game.platformSlug ?? '') : const [],
            fullscreen: prefs != null && Fullscreen.supports(s.emulatorId)
                ? Fullscreen.isOn(prefs, s.emulatorId)
                : null,
          ),
      ],
      remembered: choices.remembered,
      platformDefault: choices.platformDefault,
      catalog: catalog,
    );
  }

  @override
  Future<EmulatorStrategy?> emulatorFor(Game game, {String? emulatorId}) async {
    final registry = _ref.read(strategyRegistryProvider);
    if (registry == null) return null;
    if (emulatorId != null) return registry.getStrategyById(emulatorId);
    final slug = game.platformSlug;
    if (slug == null) return null;
    return registry.getStrategyForSlug(slug, gameId: game.id);
  }

  @override
  Stream<List<ResumeEntry>> statesFor(Game game) async* {
    final resume = _ref.read(resumeServiceProvider);
    final romPath = await romPathFor(game);
    if (resume == null || romPath == null) {
      yield const [];
      return;
    }
    yield* resume.entriesFor(game, [romPath]);
  }

  @override
  Future<StatePull> pullStates(
    Game game,
    String romPath,
    EmulatorStrategy strategy, {
    String? priority,
    String? coreOverride,
    void Function(String)? onProblem,
  }) async {
    final states = _ref.read(stateSyncServiceProvider);
    final romm = _ref.read(rommServiceProvider);
    if (states == null || !states.isAvailableFor(game, emulatorId: strategy.emulatorId)) return const StatePull();
    if (romm == null || romm.isOffline.value) return const StatePull();
    try {
      final r = await states.pullStates(
        game,
        romPath,
        emulatorId: strategy.emulatorId,
        priority: priority,
        coreOverride: coreOverride,
      );
      if (r.conflicts.isNotEmpty) {
        onProblem?.call(
          '${r.conflicts.length == 1 ? 'A state differs' : '${r.conflicts.length} states differ'} '
          "on RomM and this PC. This PC's copy is used; RomM's stays on RomM.",
        );
      }
      return StatePull(current: r.currentFiles, conflicted: {for (final c in r.conflicts) c.fileName});
    } on Object {
      return const StatePull();
    }
  }

  @override
  Future<ResumeCheck> checkResume(ResumeEntry entry, Game game, String romPath, StatePull pull) async {
    final resume = _ref.read(resumeServiceProvider);
    if (resume == null) return const ResumeMissing();
    return resume.checkBeforeLaunch(entry, game, romPath, pulled: pull.current, conflicted: pull.conflicted);
  }

  @override
  Future<void> remember(Game game, PlayRequest request) async {
    final registry = _ref.read(strategyRegistryProvider);
    if (registry == null) return;
    if (request.remember) {
      await registry.setGameEmulatorPreference(game.id, request.emulator.emulatorId);
      final core = request.emulator.coreId;
      if (core != null) await registry.setGameCorePreference(game.id, '${core}_libretro');
    } else if (request.forget) {
      await registry.clearGameEmulatorPreference(game.id);
      await registry.clearGameCorePreference(game.id);
    }
  }

  @override
  Future<void> openEmulator(String emulatorId, String exePath, {required void Function() onExit}) async {
    final dirs = _ref.read(launchDirectoriesProvider) ?? (throw StateError('No profile is active.'));
    final process = await dirs.openEmulator(emulatorId, exePath);
    process.exitCode.whenComplete(onExit);
  }

  @override
  Future<bool> isInstalled(EmulatorStrategy strategy) async {
    if (!ProfileLaunchConfig.supported.contains(strategy.emulatorId)) return false;
    final dirs = _ref.read(launchDirectoriesProvider);
    return dirs != null && await dirs.findEmulatorExecutable(strategy.emulatorId, strategy.windowsExecutable) != null;
  }

  @override
  Future<String?> romPathFor(Game game) async {
    final files = _ref.read(romFilesProvider);
    if (!files.isDownloaded(game)) return null;
    return (await _launch()).resolveRomFileInDirectory(files.pathFor(game), game.platformSlug);
  }

  @override
  Future<String> readyRom(
    Game game,
    String romPath,
    EmulatorStrategy strategy, {
    void Function(String)? onProgress,
  }) async {
    final root = _ref.read(appRootProvider);
    final preparer = RomPreparer(
      files: _ref.read(romFilesProvider),
      guard: PathGuard(root),
      tempDir: p.join(root.appData, 'temp'),
    );
    final unpacked = await preparer.ready(game, romPath, strategy.emulatorId, onProgress: onProgress);
    if (unpacked == null) return romPath;
    // The unpacked folder's main ROM, readied too (an Xbox disc unpacked
    // as it is by another path still gets its XISO check).
    final rom = await romPathFor(game) ?? (throw StateError('${game.displayName} is gone after unpacking'));
    await preparer.ready(game, rom, strategy.emulatorId, onProgress: onProgress);
    return rom;
  }

  @override
  Future<void> prepare(
    Game game,
    String romPath,
    EmulatorStrategy strategy, {
    PlayRequest? request,
    String? coreOverride,
    void Function(String)? onProblem,
  }) async {
    final sync = _ref.read(saveSyncServiceProvider);
    final backups = _ref.read(backupServiceProvider);
    final repo = await _ref.read(backupRepositoryProvider.future);
    final dirs = _ref.read(saveDirectoriesProvider);
    if (sync == null || backups == null || repo == null || dirs == null) return;
    // A new profile: the emulator's folders exist before the first save goes in.
    EmulatorLayout.of(strategy.emulatorId).ensureFolders(dirs.dataDir(strategy.emulatorId));
    // A moved Gargosy folder: the stored settings point here again first.
    _ref.read(launchDirectoriesProvider)?.repoint(strategy.emulatorId);
    final preparer = PlayPreparer(sync: sync, backups: backups, repository: repo);
    if (request != null) {
      await placeChosenSave(
        request,
        putInPlace: (save) => preparer.prepare(game, romPath, save, target: request.emulator),
        confirmRommCopy: sync.confirmRommCopy,
        markSynced: () => sync.markSaveSynced(
          game,
          romPath,
          emulatorId: strategy.emulatorId,
          syncMode: _syncMode,
          coreOverride: coreOverride,
        ),
      );
      return;
    }
    await pullBeforeLaunch(
      backUp: () => preparer.backUp(game, romPath, SaveMaker(strategy.emulatorId, coreId: _bareCore(coreOverride))),
      pull: () => sync.pullSave(game, romPath, emulatorId: strategy.emulatorId, coreOverride: coreOverride),
      markSynced: () => sync.markSaveSynced(
        game,
        romPath,
        emulatorId: strategy.emulatorId,
        syncMode: _syncMode,
        coreOverride: coreOverride,
      ),
      // Only a resume gets here (the play screen always sends its choice):
      // the state boots with the save in memory, so the pull lands first or
      // not at all, never under a running emulator.
      mustFinish: () async => true,
      onProblem: onProblem,
    );
  }

  Future<String> _romPath(Game game) async =>
      await romPathFor(game) ?? (throw StateError('the game is not on this PC'));

  Future<PlayPreparer> _preparer() async {
    final sync = _ref.read(saveSyncServiceProvider);
    final backups = _ref.read(backupServiceProvider);
    final repo = await _ref.read(backupRepositoryProvider.future);
    if (sync == null || backups == null || repo == null) throw StateError('no profile is active');
    return PlayPreparer(sync: sync, backups: backups, repository: repo);
  }

  static String? _core(SaveMaker who) => who.coreId == null ? null : '${who.coreId}_libretro';

  @override
  Future<void> restore(Game game, SaveEntry save, SaveMaker target) async =>
      (await _preparer()).prepare(game, await _romPath(game), save, target: target);

  @override
  Future<void> deleteSave(Game game, SaveEntry save) async {
    switch (save.source) {
      case SaveSource.romm:
        final id = save.rommSave?['id'];
        final romm = _ref.read(rommServiceProvider);
        if (id is! int || romm == null) throw StateError('RomM has no id for this save');
        if (!await romm.deleteSaves([id])) throw StateError('RomM refused');
      case SaveSource.backup:
        final entry = save.backup;
        final repo = await _ref.read(backupRepositoryProvider.future);
        if (entry == null || repo == null) throw StateError('the backup is gone');
        await repo.removeEntry(game.id, entry);
        final zip = io.File(entry.localZipPath);
        if (zip.existsSync()) zip.deleteSync();
      case SaveSource.local:
        throw StateError("this PC's own save isn't deleted from here");
    }
  }

  @override
  Future<bool> upload(Game game, SaveMaker who) async {
    final sync = _ref.read(saveSyncServiceProvider);
    if (sync == null) return false;
    return sync.pushSaves(game, await _romPath(game), emulatorId: who.emulatorId, coreOverride: _core(who));
  }

  @override
  Future<void> backUpNow(Game game, SaveMaker who) async => (await _preparer()).backUp(game, await _romPath(game), who);

  @override
  Future<List<String>> unclaimedSaves(Game game, SaveMaker who) async {
    final sync = _ref.read(saveSyncServiceProvider);
    final romPath = await romPathFor(game);
    if (sync == null || romPath == null) return const [];
    return sync.unclaimedSaves(game, romPath, emulatorId: who.emulatorId, coreOverride: _core(who));
  }

  @override
  Future<bool> claimSave(Game game, SaveMaker who, String name) async {
    final sync = _ref.read(saveSyncServiceProvider);
    if (sync == null) return false;
    final romPath = await _romPath(game);
    await sync.claimSave(game, romPath, name, emulatorId: who.emulatorId, coreOverride: _core(who));
    return sync.pushSaves(game, romPath, emulatorId: who.emulatorId, coreOverride: _core(who));
  }

  String? _emulatorIdOf(Game game) {
    final slug = game.platformSlug;
    return slug == null
        ? null
        : _ref.read(strategyRegistryProvider)?.getStrategyForSlug(slug, gameId: game.id)?.emulatorId;
  }

  @override
  bool stateSyncAvailable(Game game) {
    final states = _ref.read(stateSyncServiceProvider);
    final id = _emulatorIdOf(game);
    return states != null && id != null && states.isAvailableFor(game, emulatorId: id);
  }

  @override
  Future<String> syncStatesNow(Game game) async {
    final states = _ref.read(stateSyncServiceProvider);
    final id = _emulatorIdOf(game);
    if (states == null || id == null) return "Save states can't be synced for this game.";
    final romPath = await _romPath(game);
    final down = await states.pullStates(game, romPath, emulatorId: id);
    final up = await states.pushStates(game, romPath, emulatorId: id);
    if (down.skipped && up.skipped) return "Save states can't be synced for this game.";
    String n(int k) => k == 1 ? '1 state' : '$k states';
    return '${n(down.downloaded)} down, ${up.uploaded} up';
  }

  @override
  Future<bool> setRommUser(
    Game game, {
    String? status,
    int? rating,
    int? completion,
    bool? backlogged,
    bool? nowPlaying,
  }) async {
    final romm = _ref.read(rommServiceProvider);
    if (romm == null) return false;
    return romm.updateRomProps(
      game.id,
      status: status,
      rating: rating,
      completion: completion,
      backlogged: backlogged,
      nowPlaying: nowPlaying,
    );
  }

  @override
  Future<void> installCore(EmulatorStrategy strategy, MissingRetroArchCoreException missing) async {
    if (strategy is! RetroArchStrategy) throw StateError('${strategy.name} has no cores');
    // Only ever into the RetroArch install under emulators\.
    final core = PathGuard(_ref.read(appRootProvider)).check(missing.corePath);
    await strategy.downloadCore(missing.coreName, p.dirname(core), Dio());
    if (!io.File(core).existsSync()) throw StateError("The ${coreLabel(missing.coreName)} core couldn't be downloaded");
  }

  @override
  Future<void> setFullscreen(String emulatorId, bool on) async {
    final prefs = _ref.read(profilePrefsProvider);
    if (prefs != null) await Fullscreen.set(prefs, emulatorId, on);
  }

  static const _syncMode = 'both';

  static String? _bareCore(String? core) => core?.replaceAll(RegExp(r'_libretro$'), '');

  @override
  Future<PlaySession> launch(
    Game game,
    String romPath,
    EmulatorStrategy strategy, {
    String? coreOverride,
    String? loadStatePath,
  }) async {
    final service = await _launch();
    final statePath = loadStatePath == null ? null : await _stateForThisPc(strategy, loadStatePath, romPath);
    final session = await service.launch(
      game,
      romPath,
      strategy,
      overrideCoreId: coreOverride,
      loadStatePath: statePath,
    );
    final finished = service
        .awaitExitAndSync(session, game, romPath, syncMode: _syncMode, overrideCoreId: coreOverride)
        .then(_describe)
        .whenComplete(() async {
          if (statePath == loadStatePath) return;
          try {
            await io.File(statePath!).delete();
          } on io.FileSystemException catch (_) {
            // Left in temp; the next Resume of that state writes over it.
          }
        });
    return PlaySession(finished);
  }

  /// The state Resume starts: a copy in `userdata\app\temp\resume\` when
  /// the emulator needs it changed for this PC's [romPath]
  /// ([EmulatorStrategy.stateForRom]: DuckStation's disc path), else
  /// [statePath] itself. The synced file is never changed, so it isn't
  /// uploaded again. Any failure starts the state as it is.
  Future<String> _stateForThisPc(EmulatorStrategy strategy, String statePath, String romPath) async {
    try {
      final changed = strategy.stateForRom(await io.File(statePath).readAsBytes(), romPath);
      if (changed == null) return statePath;
      final root = _ref.read(appRootProvider);
      final copy = p.join(root.appData, 'temp', 'resume', p.basename(statePath));
      await writeBytesAtomic(PathGuard(root), copy, changed);
      debugPrint("[Resume] ${p.basename(statePath)}: started from a copy naming this PC's ROM");
      return copy;
    } catch (e) {
      debugPrint('[Resume] ${p.basename(statePath)}: kept as it is: $e');
      return statePath;
    }
  }

  static PlayResult _describe(LaunchResult? r) {
    if (r == null) return const PlayResult('The game ended.');
    if (r.saveConflict != null) {
      return const PlayResult(
        "RomM has a newer save from another device. It stays on RomM; yours is backed up on this PC.",
      );
    }
    if (r.saveSyncBlocked != null) return PlayResult('Saves not synced: ${r.saveSyncBlocked}');
    if (r.saveUnchanged) return const PlayResult('Save unchanged.', synced: true);
    if (r.syncOk) return const PlayResult('Save synced to RomM.', synced: true);
    return const PlayResult('No save to upload.');
  }
}

final playEngineProvider = Provider<PlayEngine?>((ref) => GargosyPlayEngine(ref));
