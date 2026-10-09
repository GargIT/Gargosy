import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_models.dart';
import '../providers/library_providers.dart';
import 'play_engine.dart';

class PlayState {
  const PlayState({this.runningGameId, this.message});

  /// The game being played right now (one at a time, spec §6).
  final String? runningGameId;

  /// What the last session said when it ended.
  final String? message;
}

/// Playing a game: the profile's save in place, the emulator on the profile's
/// data, the saves synced after (spec §6). One game at a time.
class PlayController extends StateNotifier<PlayState> {
  PlayController(this._ref) : super(const PlayState());

  final Ref _ref;

  /// Starts [game]; returns why it couldn't, or null. [onNotice] hears
  /// what the player should know but doesn't stop the game (a save that
  /// couldn't be pulled).
  Future<String?> play(Game game, {void Function(String)? onNotice}) async {
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
      final romPath = await engine.romPathFor(game);
      if (romPath == null) return refuse('Download the game first.');
      final emulator = await engine.emulatorFor(game);
      if (emulator == null) return refuse('No emulator plays ${game.platformDisplayName ?? 'this platform'} yet.');
      if (!await engine.isInstalled(emulator)) {
        return refuse('${emulator.name} is needed. Install it under Emulators (Start → Emulators).');
      }
      await engine.pullSave(game, romPath, emulator, onProblem: onNotice);
      final session = await engine.launch(game, romPath, emulator);
      session.finished.then((result) => _ended(game, result.message), onError: (Object e) => _ended(game, 'Saves not synced: $e'));
      return null;
    } on Object catch (e) {
      return refuse("Couldn't start ${game.displayName}: $e");
    }
  }

  void _ended(Game game, String message) {
    if (!mounted) return;
    state = PlayState(message: message);
    _ref.invalidate(romSavesProvider(game.id));
    _ref.invalidate(romStatesProvider(game.id));
  }
}

final playControllerProvider = StateNotifierProvider<PlayController, PlayState>((ref) => PlayController(ref));
