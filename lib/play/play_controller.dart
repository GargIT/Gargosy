import '../core/emulator/strategies/retroarch_strategy.dart';
import '../core/emulator/emulator_strategy.dart';

import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_models.dart';
import '../core/save/catalog/play_request.dart';
import '../core/save/resume_service.dart';
import '../core/save/save_sync_service.dart';
import '../providers/library_providers.dart';
import '../library/upload_queue.dart';
import 'play_engine.dart';
import 'play_menu.dart';

class PlayState {
  const PlayState({this.runningGameId, this.message, this.preparing});

  /// The game being played right now (one at a time, spec §6).
  final String? runningGameId;

  /// What the last session said when it ended.
  final String? message;

  /// While the game's ROM is readied before launch (a zip unpacked, an
  /// Xbox disc converted): what's happening, with a percentage.
  final String? preparing;
}

/// Playing a game: the profile's save in place, the emulator on the profile's
/// data, the saves synced after (spec §6). One game at a time.
class PlayController extends StateNotifier<PlayState> {
  PlayController(this._ref) : super(const PlayState());

  final Ref _ref;

  /// Starts [game]; returns why it couldn't, or null. [onNotice] hears
  /// what the player should know but doesn't stop the game (a save that
  /// couldn't be pulled).
  ///
  /// [request] is the play screen's choice of save and emulator; without
  /// it the game plays in its emulator with the profile's RomM save.
  Future<String?> play(Game game, {PlayRequest? request, void Function(String)? onNotice}) async {
    if (state.runningGameId != null) return 'A game is already running. Close it first.';
    // Taken before the first await: a second press, or a profile switch,
    // while this one is still starting is refused too.
    state = PlayState(runningGameId: game.id);
    String? refuse(String reason) {
      state = const PlayState();
      return reason;
    }

    try {
      final engine = _ref.read(playEngineProvider);
      if (engine == null) return refuse('No profile is active.');
      final foundRom = await engine.romPathFor(game);
      if (foundRom == null) return refuse('Download the game first.');
      final emulator = await engine.emulatorFor(game, emulatorId: request?.emulator.emulatorId);
      if (emulator == null) return refuse('No emulator plays ${game.platformDisplayName ?? 'this platform'} yet.');
      if (!await engine.isInstalled(emulator)) {
        return refuse('${emulator.name} is needed. Install it under Emulators (Start → Emulators).');
      }
      final String romPath;
      try {
        romPath = await _ready(engine, game, foundRom, emulator);
      } on Object catch (e) {
        return refuse("Couldn't start ${game.displayName}: $e");
      }
      final core = request?.emulator.coreId;
      final coreOverride = core == null ? null : '${core}_libretro';
      if (request != null) {
        await engine.remember(game, request);
        // The game page's menu (its "Forget Always in …") shows the new choice.
        _ref.invalidate(playMenuProvider(PlayMenuKey(game)));
      }
      await engine.pullStates(game, romPath, emulator, coreOverride: coreOverride, onProblem: onNotice);
      await engine.prepare(game, romPath, emulator, request: request, coreOverride: coreOverride, onProblem: onNotice);
      final session = await _launch(engine, game, romPath, emulator, coreOverride: coreOverride, onNotice: onNotice);
      session.finished.then(
        (result) => _ended(game, result.message, synced: result.synced),
        onError: (Object e) => _ended(game, 'Saves not synced: $e'),
      );
      return null;
    } on SaveChoiceException catch (e) {
      return refuse("Couldn't start with that save: ${e.message}");
    } on StateError catch (e) {
      return refuse("Couldn't start ${game.displayName}: ${e.message}");
    } on Object catch (e) {
      return refuse("Couldn't start ${game.displayName}: $e");
    }
  }

  /// Gargosy: what [PlayState.runningGameId] holds while an emulator is open
  /// on its own (no game): launches, profile switches and updates wait for
  /// it as for a game.
  static String openEmulatorId(String emulatorId) => 'emulator:$emulatorId';

  /// Opens [emulatorId] (at [exePath]) on the profile's data with no game,
  /// for its own settings (controllers). Returns why it couldn't, or null.
  Future<String?> openEmulator(String emulatorId, String name, String exePath) async {
    if (state.runningGameId != null) return 'A game is running. Close it first.';
    state = PlayState(runningGameId: openEmulatorId(emulatorId));
    try {
      final engine = _ref.read(playEngineProvider);
      if (engine == null) {
        state = const PlayState();
        return 'No profile is active.';
      }
      await engine.openEmulator(
        emulatorId,
        exePath,
        onExit: () {
          if (mounted) state = const PlayState();
        },
      );
      return null;
    } on Object catch (e) {
      state = const PlayState();
      return "Couldn't open $name: $e";
    }
  }

  /// Resumes [game] from the save state [entry], in the emulator that made
  /// it and from the ROM file it belongs to. [confirmVersion] is asked when
  /// the state comes from another build of the emulator; false starts
  /// nothing. Returns why it couldn't start, or null.
  Future<String?> resume(
    Game game,
    ResumeEntry entry, {
    Future<bool> Function(String stateVersion, String installed)? confirmVersion,
    void Function(String)? onNotice,
  }) async {
    if (state.runningGameId != null) return 'A game is already running. Close it first.';
    state = PlayState(runningGameId: game.id);
    String? refuse(String reason) {
      state = const PlayState();
      return reason;
    }

    try {
      final engine = _ref.read(playEngineProvider);
      if (engine == null) return refuse('No profile is active.');
      // A state belongs to one disc: it boots the ROM file it was made with.
      final own = entry.romPath;
      final foundRom = own != null && io.File(own).existsSync() ? own : await engine.romPathFor(game);
      if (foundRom == null) return refuse('Download the game first.');
      final emulator = await engine.emulatorFor(game, emulatorId: entry.emulatorId);
      if (emulator == null || !await engine.isInstalled(emulator)) {
        return refuse('${entry.emulatorName} is needed. Install it under Emulators (Start → Emulators).');
      }
      final romPath = await _ready(engine, game, foundRom, emulator);
      // The core the state was made with (RetroArch), not the platform's default.
      final coreOverride = entry.core == null ? null : '${entry.core}_libretro';
      final pull = await engine.pullStates(
        game,
        romPath,
        emulator,
        priority: entry.fileName,
        coreOverride: coreOverride,
        onProblem: onNotice,
      );
      final String loadPath;
      switch (await engine.checkResume(entry, game, romPath, pull)) {
        case ResumeMissing():
          return refuse(resumeMissingMessage(entry, serviceAvailable: true));
        case ResumeReady(:final path, :final stale, :final prompt):
          if (prompt != null &&
              (confirmVersion == null || !await confirmVersion(prompt.stateVersion, prompt.installed))) {
            return refuse('Nothing was started.');
          }
          if (stale) onNotice?.call("Couldn't update ${entry.slot.label} from RomM. Loading the copy on this PC.");
          loadPath = path;
      }
      await engine.prepare(game, romPath, emulator, coreOverride: coreOverride, onProblem: onNotice);
      final session = await _launch(
        engine,
        game,
        romPath,
        emulator,
        coreOverride: coreOverride,
        loadStatePath: loadPath,
        onNotice: onNotice,
      );
      session.finished.then(
        (result) => _ended(game, result.message, synced: result.synced),
        onError: (Object e) => _ended(game, 'Saves not synced: $e'),
      );
      return null;
    } on Object catch (e) {
      return refuse("Couldn't start ${game.displayName}: $e");
    }
  }

  /// [engine.readyRom] with its progress in [PlayState.preparing], cleared after.
  Future<String> _ready(PlayEngine engine, Game game, String romPath, EmulatorStrategy emulator) async {
    try {
      return await engine.readyRom(
        game,
        romPath,
        emulator,
        onProgress: (s) => state = PlayState(runningGameId: game.id, preparing: s),
      );
    } finally {
      if (state.preparing != null) state = PlayState(runningGameId: game.id);
    }
  }

  /// Launches; a RetroArch core that isn't installed yet is downloaded first
  /// (RetroArch's download brings only a few), then the launch runs again.
  Future<PlaySession> _launch(
    PlayEngine engine,
    Game game,
    String romPath,
    EmulatorStrategy emulator, {
    String? coreOverride,
    String? loadStatePath,
    void Function(String)? onNotice,
  }) async {
    try {
      return await engine.launch(game, romPath, emulator, coreOverride: coreOverride, loadStatePath: loadStatePath);
    } on MissingRetroArchCoreException catch (missing) {
      onNotice?.call('Downloading the ${coreLabel(missing.coreName)} core for RetroArch…');
      await engine.installCore(emulator, missing);
      return engine.launch(game, romPath, emulator, coreOverride: coreOverride, loadStatePath: loadStatePath);
    }
  }

  void _ended(Game game, String message, {bool synced = false}) {
    if (!mounted) return;
    // What waited to upload for this game is older than what RomM has now.
    if (synced) _ref.read(uploadQueueProvider.future).then((q) => q?.settle(game.id)).catchError((Object _) {});
    state = PlayState(message: message);
    _ref.invalidate(romSavesProvider(game.id));
    _ref.invalidate(romStatesProvider(game.id));
    _ref.read(uploadQueueVersionProvider.notifier).state++;
  }
}

final playControllerProvider = StateNotifierProvider<PlayController, PlayState>((ref) => PlayController(ref));

/// Identifies a game for [playMenuProvider] (Game has no value equality).
class PlayMenuKey {
  const PlayMenuKey(this.game);
  final Game game;
  @override
  bool operator ==(Object other) =>
      other is PlayMenuKey && other.game.id == game.id && other.game.fsName == game.fsName;
  @override
  int get hashCode => Object.hash(game.id, game.fsName);
}

/// The play screen's emulators and saves for a game; re-read when the
/// screen opens.
final playMenuProvider = FutureProvider.autoDispose.family<PlayMenu?, PlayMenuKey>((ref, key) async {
  final engine = ref.watch(playEngineProvider);
  return engine?.menuFor(key.game);
});

/// The saves on the shared volume (Flycast's VMU) that no game owns, for
/// the game's emulator (#56); empty for the rest.
final unclaimedSavesProvider = FutureProvider.autoDispose.family<List<String>, PlayMenuKey>((ref, key) async {
  final engine = ref.watch(playEngineProvider);
  final who = (await ref.watch(playMenuProvider(key).future))?.forThisGame;
  if (engine == null || who == null) return const [];
  return engine.unclaimedSaves(key.game, who);
});

/// The states the play screen lists for a game: this PC's first, then
/// merged with RomM's.
final playStatesProvider = StreamProvider.autoDispose.family<List<ResumeEntry>, PlayMenuKey>((ref, key) {
  final engine = ref.watch(playEngineProvider);
  return engine?.statesFor(key.game) ?? Stream.value(const []);
});
