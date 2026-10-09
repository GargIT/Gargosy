import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emulator/emulator_strategy.dart';
import '../core/emulator/game_launch_service.dart';
import '../core/romm/romm_models.dart';
import '../core/save/catalog/play_preparer.dart';
import '../core/save/catalog/save_maker.dart';
import '../emulators/emulator_layout.dart';
import '../emulators/profile_launch_config.dart';
import '../providers/download_providers.dart';
import '../providers/engine_providers.dart';
import 'pre_launch_pull.dart';

/// What a finished session says ("Save synced", …).
class PlayResult {
  const PlayResult(this.message);
  final String message;
}

/// A running game; [finished] completes once it exits and its saves synced.
class PlaySession {
  const PlaySession(this.finished);
  final Future<PlayResult> finished;
}

/// The steps of playing a game, as Freegosy's launch flow does them. The real
/// one is [GargosyPlayEngine]; tests use a fake.
abstract class PlayEngine {
  Future<EmulatorStrategy?> emulatorFor(Game game);
  Future<bool> isInstalled(EmulatorStrategy strategy);

  /// The ROM to start, or null when the game isn't downloaded.
  Future<String?> romPathFor(Game game);

  /// Backs up this PC's save, then puts the profile's RomM save in place.
  /// Never throws for a save problem: [onProblem] is told instead.
  Future<void> pullSave(Game game, String romPath, EmulatorStrategy strategy, {void Function(String)? onProblem});
  Future<PlaySession> launch(Game game, String romPath, EmulatorStrategy strategy);
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
  Future<EmulatorStrategy?> emulatorFor(Game game) async {
    final slug = game.platformSlug;
    if (slug == null) return null;
    return _ref.read(strategyRegistryProvider)?.getStrategyForSlug(slug, gameId: game.id);
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
  Future<void> pullSave(Game game, String romPath, EmulatorStrategy strategy, {void Function(String)? onProblem}) async {
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
    await pullBeforeLaunch(
      backUp: () => preparer.backUp(game, romPath, SaveMaker(strategy.emulatorId)),
      pull: () => sync.pullSave(game, romPath, emulatorId: strategy.emulatorId),
      markSynced: () => sync.markSaveSynced(game, romPath, emulatorId: strategy.emulatorId, syncMode: 'both'),
      mustFinish: () async =>
          await sync.getStrategyForGame(game, emulatorId: strategy.emulatorId)?.pullMustFinishBeforeLaunch(game, romPath) ??
          false,
      onProblem: onProblem,
    );
  }

  @override
  Future<PlaySession> launch(Game game, String romPath, EmulatorStrategy strategy) async {
    final service = await _launch();
    final session = await service.launch(game, romPath, strategy);
    final finished = service.awaitExitAndSync(session, game, romPath, syncMode: 'both').then(_describe);
    return PlaySession(finished);
  }

  static PlayResult _describe(LaunchResult? r) {
    if (r == null) return const PlayResult('The game ended.');
    if (r.saveConflict != null) {
      return const PlayResult("RomM has a newer save from another device. It stays on RomM; yours is backed up on this PC.");
    }
    if (r.saveSyncBlocked != null) return PlayResult('Saves not synced: ${r.saveSyncBlocked}');
    if (r.saveUnchanged) return const PlayResult('Save unchanged.');
    if (r.syncOk) return const PlayResult('Save synced to RomM.');
    return const PlayResult('No save to upload.');
  }
}

final playEngineProvider = Provider<PlayEngine?>((ref) => GargosyPlayEngine(ref));
