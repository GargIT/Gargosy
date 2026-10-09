import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_models.dart';
import '../core/save/catalog/save_entry.dart';
import '../core/save/catalog/save_maker.dart';
import '../core/save/save_sync_service.dart';
import '../providers/library_providers.dart';
import 'play_controller.dart';
import 'play_engine.dart';

/// What the game page and its Saves tab do with a game's saves (spec Part 3):
/// put one on this PC, delete one, upload, back up, sync states. Each says
/// why it couldn't, or null; none runs while a game of this profile runs
/// (the game has the emulator's files open); after a change the save list
/// is read again.
class SaveActions {
  SaveActions(this._ref);
  final Ref _ref;

  Future<String?> _run(Game game, String what, Future<void> Function(PlayEngine engine) body) async {
    if (_ref.read(playControllerProvider).runningGameId != null) {
      return "Close the game first: its saves can't change while it runs.";
    }
    final engine = _ref.read(playEngineProvider);
    if (engine == null) return 'No profile is active.';
    try {
      await body(engine);
      return null;
    } on SaveChoiceException catch (e) {
      return "Couldn't $what: ${e.message}";
    } on StateError catch (e) {
      return "Couldn't $what: ${e.message}.";
    } on Object catch (e) {
      return "Couldn't $what: $e";
    } finally {
      final key = PlayMenuKey(game);
      _ref.invalidate(playMenuProvider(key));
      _ref.invalidate(playStatesProvider(key));
      _ref.invalidate(romSavesProvider(game.id));
      _ref.invalidate(romStatesProvider(game.id));
    }
  }

  Future<String?> restore(Game game, SaveEntry save, SaveMaker target) =>
      _run(game, 'put the save on this PC', (e) => e.restore(game, save, target));

  Future<String?> delete(Game game, SaveEntry save) => _run(game, 'delete the save', (e) => e.deleteSave(game, save));

  Future<String?> upload(Game game, SaveMaker who) => _run(game, 'upload the save', (e) async {
        if (!await e.upload(game, who)) throw StateError("RomM didn't take it");
      });

  Future<String?> backUpNow(Game game, SaveMaker who) => _run(game, 'back up the save', (e) => e.backUpNow(game, who));

  /// What moved, or why nothing could.
  Future<String> syncStates(Game game) async {
    String? message;
    final refused = await _run(game, 'sync save states', (e) async => message = await e.syncStatesNow(game));
    return refused ?? message ?? '';
  }
}

final saveActionsProvider = Provider<SaveActions>((ref) => SaveActions(ref));
