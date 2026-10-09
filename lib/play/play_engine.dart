import '../profiles/profile_providers.dart';
import '../profiles/path_guard.dart';
import '../core/emulator/strategies/retroarch_strategy.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'dart:io' as io;
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emulator/emulator_strategy.dart';
import '../core/emulator/game_launch_service.dart';
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

  /// Backs up this PC's save, then puts the profile's RomM save in place.
  /// The states [game] can be resumed from: this PC's first, then merged
  /// with RomM's.
  Stream<List<ResumeEntry>> statesFor(Game game);

  /// Brings the profile's states down from RomM before launch (when state
  /// sync is on for the emulator and RomM is reachable); [priority] first.
  /// Never throws.
  Future<StatePull> pullStates(Game game, String romPath, EmulatorStrategy strategy,
      {String? priority, String? coreOverride, void Function(String)? onProblem});

  /// Whether [entry] can be loaded now (after [pull]).
  Future<ResumeCheck> checkResume(ResumeEntry entry, Game game, String romPath, StatePull pull);

  /// Stores or forgets [game]'s emulator as [request] says.
  Future<void> remember(Game game, PlayRequest request);

  /// Puts the save in place before launch. With [request], the save the
  /// play screen chose (null: the emulator's own save on this PC), and a
  /// failure stops the launch (SaveChoiceException). Without, this PC's
  /// save is backed up and the profile's RomM save pulled; that never
  /// throws for a save problem: [onProblem] is told instead.
  Future<void> prepare(Game game, String romPath, EmulatorStrategy strategy,
      {PlayRequest? request, String? coreOverride, void Function(String)? onProblem});
  Future<PlaySession> launch(Game game, String romPath, EmulatorStrategy strategy,
      {String? coreOverride, String? loadStatePath});

  /// Downloads the RetroArch core [missing] names into the RetroArch install
  /// (shared by every profile). Throws when it can't.
  Future<void> installCore(EmulatorStrategy strategy, MissingRetroArchCoreException missing);
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
          sync: sync, registry: registry, backupRepository: repo, rommService: _ref.read(rommServiceProvider), installed: installed),
    );
    return PlayMenu(
      emulators: [
        for (final s in choices.emulators)
          EmulatorOption(choices.makerFor(s.emulatorId), choices.nameOf(choices.makerFor(s.emulatorId))),
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
  Future<StatePull> pullStates(Game game, String romPath, EmulatorStrategy strategy,
      {String? priority, String? coreOverride, void Function(String)? onProblem}) async {
    final states = _ref.read(stateSyncServiceProvider);
    final romm = _ref.read(rommServiceProvider);
    if (states == null || !states.isAvailableFor(game, emulatorId: strategy.emulatorId)) return const StatePull();
    if (romm == null || romm.isOffline.value) return const StatePull();
    try {
      final r = await states.pullStates(game, romPath,
          emulatorId: strategy.emulatorId, priority: priority, coreOverride: coreOverride);
      if (r.conflicts.isNotEmpty) {
        onProblem?.call('${r.conflicts.length == 1 ? 'A state differs' : '${r.conflicts.length} states differ'} '
            "on RomM and this PC. This PC's copy is used; RomM's stays on RomM.");
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
  Future<void> prepare(Game game, String romPath, EmulatorStrategy strategy,
      {PlayRequest? request, String? coreOverride, void Function(String)? onProblem}) async {
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
        markSynced: () =>
            sync.markSaveSynced(game, romPath, emulatorId: strategy.emulatorId, syncMode: _syncMode, coreOverride: coreOverride),
      );
      return;
    }
    await pullBeforeLaunch(
      backUp: () => preparer.backUp(game, romPath, SaveMaker(strategy.emulatorId, coreId: _bareCore(coreOverride))),
      pull: () => sync.pullSave(game, romPath, emulatorId: strategy.emulatorId, coreOverride: coreOverride),
      markSynced: () =>
          sync.markSaveSynced(game, romPath, emulatorId: strategy.emulatorId, syncMode: _syncMode, coreOverride: coreOverride),
      // Only a resume gets here (the play screen always sends its choice):
      // the state boots with the save in memory, so the pull lands first or
      // not at all, never under a running emulator.
      mustFinish: () async => true,
      onProblem: onProblem,
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

  static const _syncMode = 'both';

  static String? _bareCore(String? core) => core?.replaceAll(RegExp(r'_libretro$'), '');

  @override
  Future<PlaySession> launch(Game game, String romPath, EmulatorStrategy strategy,
      {String? coreOverride, String? loadStatePath}) async {
    final service = await _launch();
    final session = await service.launch(game, romPath, strategy, overrideCoreId: coreOverride, loadStatePath: loadStatePath);
    final finished = service
        .awaitExitAndSync(session, game, romPath, syncMode: _syncMode, overrideCoreId: coreOverride)
        .then(_describe);
    return PlaySession(finished);
  }

  static PlayResult _describe(LaunchResult? r) {
    if (r == null) return const PlayResult('The game ended.');
    if (r.saveConflict != null) {
      return const PlayResult("RomM has a newer save from another device. It stays on RomM; yours is backed up on this PC.");
    }
    if (r.saveSyncBlocked != null) return PlayResult('Saves not synced: ${r.saveSyncBlocked}');
    if (r.saveUnchanged) return const PlayResult('Save unchanged.', synced: true);
    if (r.syncOk) return const PlayResult('Save synced to RomM.', synced: true);
    return const PlayResult('No save to upload.');
  }
}

final playEngineProvider = Provider<PlayEngine?>((ref) => GargosyPlayEngine(ref));
