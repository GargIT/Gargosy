import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/romm/romm_models.dart';
import '../core/save/catalog/save_entry.dart';
import '../core/save/catalog/save_maker.dart';
import '../core/save/resume_service.dart';
import '../core/save/save_sync_service.dart';
import '../providers/library_providers.dart';
import '../providers/romm_providers.dart';
import 'play_controller.dart';
import 'play_engine.dart';
import '../l10n/tr.dart';

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
      return tr('Close the game first: its saves can\'t change while it runs.');
    }
    final engine = _ref.read(playEngineProvider);
    if (engine == null) return tr('No profile is active.');
    try {
      await body(engine);
      return null;
    } on SaveChoiceException catch (e) {
      return tr('Couldn\'t {0}: {1}', [what, e.message]);
    } on StateError catch (e) {
      return tr('Couldn\'t {0}: {1}.', [what, e.message]);
    } on Object catch (e) {
      return tr('Couldn\'t {0}: {1}', [what, e]);
    } finally {
      final key = PlayMenuKey(game);
      _ref.invalidate(playMenuProvider(key));
      _ref.invalidate(playStatesProvider(key));
      _ref.invalidate(romSavesProvider(game.id));
      _ref.invalidate(continueElsewhereProvider(game.id));
      _ref.invalidate(romStatesProvider(game.id));
      _ref.invalidate(unclaimedSavesProvider(key));
    }
  }

  /// The unclaimed save [name] is [game]'s (#56): claimed and uploaded.
  Future<String?> claim(Game game, SaveMaker who, String name) => _run(game, tr('take the save'), (e) async {
    if (!await e.claimSave(game, who, name)) {
      throw StateError(tr('it\'s this game\'s now, but RomM didn\'t take it yet; it goes up with the next upload'));
    }
  });

  Future<String?> restore(Game game, SaveEntry save, SaveMaker target) =>
      _run(game, tr('put the save on this PC'), (e) => e.restore(game, save, target));

  Future<String?> delete(Game game, SaveEntry save) =>
      _run(game, tr('delete the save'), (e) => e.deleteSave(game, save));

  /// Gargosy (#94): the player's own state, on this PC and on RomM.
  Future<String?> deleteState(Game game, ResumeEntry entry) => _run(game, tr('delete the state'), (e) async {
    final partly = await e.deleteState(game, entry);
    if (partly != null) throw StateError(partly);
  });

  Future<String?> upload(Game game, SaveMaker who) => _run(game, tr('upload the save'), (e) async {
    if (!await e.upload(game, who)) throw StateError(tr('RomM didn\'t take it'));
  });

  Future<String?> backUpNow(Game game, SaveMaker who) =>
      _run(game, tr('back up the save'), (e) => e.backUpNow(game, who));

  /// Gargosy (#92): shares the player's own RomM save ([saveId]) or state
  /// ([stateId]) with the other players there, or stops. Only RomM changes,
  /// so a running game doesn't matter. Why it couldn't, or null.
  Future<String?> share(Game game, {int? saveId, int? stateId, required bool shared}) async {
    final romm = _ref.read(rommServiceProvider);
    if (romm == null || romm.isOffline.value) return tr('RomM can\'t be reached.');
    try {
      final ok = saveId != null
          ? await romm.setSaveShared(saveId, shared)
          : stateId != null && await romm.setStateShared(stateId, shared);
      return ok ? null : tr('RomM didn\'t take it.');
    } finally {
      final key = PlayMenuKey(game);
      _ref.invalidate(playMenuProvider(key));
      _ref.invalidate(playStatesProvider(key));
      _ref.invalidate(romSavesProvider(game.id));
      _ref.invalidate(continueElsewhereProvider(game.id));
      _ref.invalidate(romStatesProvider(game.id));
    }
  }

  /// What moved, or why nothing could.
  Future<String> syncStates(Game game) async {
    String? message;
    final refused = await _run(game, tr('sync save states'), (e) async => message = await e.syncStatesNow(game));
    return refused ?? message ?? '';
  }
}

final saveActionsProvider = Provider<SaveActions>((ref) => SaveActions(ref));
