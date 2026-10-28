import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../core/save/catalog/play_choice.dart';
import '../../../core/save/catalog/save_count.dart';
import '../../../core/save/catalog/play_view.dart';
import '../../../core/save/catalog/save_entry.dart';
import '../../../core/save/catalog/save_maker.dart';
import '../../../core/save/resume_service.dart';
import '../../../library/upload_queue.dart';
import '../../../play/play_controller.dart';
import '../../../play/play_menu.dart';
import '../../../play/save_actions.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/save_list/save_labels.dart';
import '../../widgets/save_list/save_list.dart';
import '../../widgets/save_list/state_list.dart';
import '../../widgets/toast.dart';
import '../../../l10n/tr.dart';

/// The game page's Saves tab (spec Part 3): every save of the game, to
/// manage — put one on this PC (X), delete one (hold A), upload, back up.
/// Nothing launches from here; states are for looking at.
class SavesTab extends ConsumerStatefulWidget {
  const SavesTab({super.key, required this.game});
  final Game game;

  @override
  ConsumerState<SavesTab> createState() => _SavesTabState();
}

class _SavesTabState extends ConsumerState<SavesTab> {
  bool _states = false;

  Game get _game => widget.game;
  PlayMenuKey get _key => PlayMenuKey(_game);

  @override
  void initState() {
    super.initState();
    // RomM's saves are read fresh each time the tab opens.
    Future.microtask(() {
      if (!mounted) return;
      ref.invalidate(playMenuProvider(_key));
      ref.invalidate(playStatesProvider(_key));
    });
  }

  void _say(String? reason, String done) {
    if (mounted) showToast(context, reason ?? done);
  }

  Future<void> _restore(PlayMenu menu, PlayView view, SaveEntry save) async {
    final row = view.saveRows.where((r) => r.entry == save).firstOrNull;
    final target = row?.fit.playsIn ?? menu.forThisGame;
    if (target == null) return;
    final item = row?.item;
    final prompt = item == null ? null : view.promptFor(item);
    if (prompt != null) {
      final older = view.newestLocalFor(target);
      final ok = await showConfirm(
        context,
        title: switch (prompt) {
          PlayPrompt.notOnRomm => tr('Your save on this PC isn\'t on RomM'),
          PlayPrompt.othersSave => tr('Put {0}\'s save on this PC?', [save.owner?.username ?? 'their']),
          _ => tr('Put an older save on this PC?'),
        },
        body: tr('This replaces your {0} save{1} with the one from {2}. Your current save is backed up first.', [
          menu.nameOf(target),
          older == null ? '' : ' from ${formatSaveTime(older)}',
          formatSaveTime(save.savedAt),
        ]),
        yes: tr('Put it on this PC'),
        focusYes: false,
      );
      if (!ok || !mounted) return;
    }
    final reason = await ref.read(saveActionsProvider).restore(_game, save, target);
    _say(reason, tr('The save from {0} is on this PC now.', [formatSaveTime(save.savedAt)]));
  }

  /// Y on the player's own RomM save or state (#92).
  Future<void> _share({int? saveId, int? stateId, required bool shared}) async {
    final reason = await ref.read(saveActionsProvider).share(_game, saveId: saveId, stateId: stateId, shared: shared);
    _say(
      reason == null ? null : tr('Couldn\'t change sharing: {0}', [reason]),
      shared
          ? tr('Shared on RomM: the other players there can see it and play from it.')
          : tr('Not shared any more: it\'s yours alone again.'),
    );
  }

  /// A click (or A) on a state (#94): what can be done with it.
  Future<void> _stateMenu(ResumeEntry s) async {
    if (s.owner != null) return;
    final share = s.remoteId == null ? null : (s.shared ? tr('Stop sharing') : tr('Share on RomM'));
    final labels = [?share, tr('Delete')];
    final i = await showChoice(context, title: s.slot.label, labels: labels);
    if (i == null || !mounted) return;
    if (labels[i] == share) await _share(stateId: s.remoteId, shared: !s.shared);
    if (labels[i] == 'Delete') await _deleteState(s);
  }

  /// Hold A on the player's own state (#94).
  Future<void> _deleteState(ResumeEntry s) async {
    final where = switch (s.where) {
      ResumeWhere.thisPc => tr('on this PC'),
      ResumeWhere.romm => tr('on RomM, for every device'),
      ResumeWhere.both => tr('on this PC and on RomM, for every device'),
    };
    final ok = await showConfirm(
      context,
      title: tr('Delete this state?'),
      body: tr('{0} in {1} ({2}) is deleted {3}.', [s.slot.label, s.emulatorName, formatSaveTime(s.savedAt), where]),
      yes: tr('Delete'),
      no: tr('Keep'),
      focusYes: false,
      danger: true,
    );
    if (!ok || !mounted) return;
    final reason = await ref.read(saveActionsProvider).deleteState(_game, s);
    _say(reason, tr('Deleted.'));
  }

  Future<void> _delete(SaveEntry save) async {
    if (save.source == SaveSource.local) return _deleteLocal(save);
    final romm = save.source == SaveSource.romm;
    final ok = await showConfirm(
      context,
      title: romm ? tr('Delete this save from RomM?') : tr('Delete this backup?'),
      body: romm
          ? tr('{0} ({1}) is deleted on RomM, for every device.', [save.fileName, formatSaveTime(save.savedAt)])
          : tr('The backup from {0} is deleted from this PC.', [formatSaveTime(save.savedAt)]),
      yes: tr('Delete'),
      no: tr('Keep'),
      focusYes: false,
      danger: true,
    );
    if (!ok || !mounted) return;
    final reason = await ref.read(saveActionsProvider).delete(_game, save);
    _say(reason, tr('Deleted.'));
  }

  /// This PC's own save (#94): backed up, then deleted; RomM's copy stays.
  Future<void> _deleteLocal(SaveEntry save) async {
    final ok = await showConfirm(
      context,
      title: tr('Delete this PC\'s save?'),
      body: tr(
        'The {0} save on this PC ({1}) is deleted. A backup is kept here first. RomM\'s copy stays, and comes back the next time you play.',
        [save.tag ?? save.maker?.emulatorId ?? '', formatSaveTime(save.savedAt)],
      ),
      yes: tr('Delete'),
      no: tr('Keep'),
      focusYes: false,
      danger: true,
    );
    if (!ok || !mounted) return;
    final reason = await ref.read(saveActionsProvider).delete(_game, save);
    _say(reason, tr('Deleted on this PC. It\'s in the backups.'));
  }

  /// The shared card's name for the game's system.
  String get _volume =>
      const {'dc', 'dreamcast'}.contains(_game.platformSlug?.toLowerCase()) ? 'VMU' : tr('memory card');

  Future<void> _claim(SaveMaker who, String name) async {
    final ok = await showConfirm(
      context,
      title: tr('Is {0} this game\'s save?', [name]),
      body: tr(
        'It goes to RomM with {0} and comes back with it on other PCs. It stays on the shared {1}, and the other games keep their saves.',
        [_game.displayName, _volume],
      ),
      yes: tr('Take it'),
      no: tr('Not this one'),
      focusYes: false,
    );
    if (!ok || !mounted) return;
    final reason = await ref.read(saveActionsProvider).claim(_game, who, name);
    _say(reason, tr('{0} is {1}\'s save now, and it\'s on RomM.', [name, _game.displayName]));
  }

  /// Saves on the shared card that no game owns (#56), to claim one.
  Widget _unclaimed(SaveMaker who, List<String> names) => Container(
    margin: const EdgeInsets.only(bottom: GSpace.s3),
    padding: const EdgeInsets.all(GSpace.s3),
    decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.lg)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Unclaimed saves on the shared {0}', [_volume]), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: GSpace.s1),
        Text(
          tr('No game is known to own these. If one is this game\'s, take it: it then syncs with this game.'),
          style: const TextStyle(color: GColors.fgSecondary),
        ),
        const SizedBox(height: GSpace.s2),
        Wrap(
          spacing: GSpace.s2,
          runSpacing: GSpace.s2,
          children: [
            for (final name in names)
              GFocusable(
                borderRadius: GRadius.pill,
                onActivate: () => _claim(who, name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
                  decoration: BoxDecoration(color: GColors.bg, borderRadius: BorderRadius.circular(GRadius.pill)),
                  child: Text(tr('{0}  ·  This is this game\'s save', [name])),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _button(String label, IconData icon, VoidCallback? onPress) => Padding(
    padding: const EdgeInsets.only(left: GSpace.s2),
    child: GFocusable(
      borderRadius: GRadius.pill,
      onActivate: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
        decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: GColors.fgSecondary),
            const SizedBox(width: GSpace.s2),
            Text(
              label,
              style: const TextStyle(color: GColors.fgSecondary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _segment(String label, bool on, VoidCallback onPress) => GFocusable(
    borderRadius: GRadius.pill,
    onActivate: onPress,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
      decoration: BoxDecoration(
        color: on ? GColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(GRadius.pill),
      ),
      child: Text(label, style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(playMenuProvider(_key));
    final statesAsync = ref.watch(playStatesProvider(_key));
    final states = statesAsync.valueOrNull ?? const <ResumeEntry>[];
    final waiting = ref.watch(uploadsWaitingProvider(_game.id));
    final unclaimed = ref.watch(unclaimedSavesProvider(_key)).valueOrNull ?? const <String>[];
    return menuAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorRetry(message: describeLoadError(e), onRetry: () => ref.invalidate(playMenuProvider(_key))),
      data: (menu) {
        if (menu == null) return const SizedBox.shrink();
        final view = buildPlayView(
          catalog: menu.catalog,
          states: states,
          platformSlug: _game.platformSlug ?? '',
          picked: menu.forThisGame,
          platformDefault: menu.platformDefault,
          installed: menu.installedIds,
          showAll: true,
        );
        final who = menu.forThisGame;
        final actions = ref.read(saveActionsProvider);
        final count = distinctSaveCount([for (final r in view.saveRows) r.entry]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (waiting.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: GSpace.s3),
                padding: const EdgeInsets.all(GSpace.s3),
                decoration: BoxDecoration(
                  color: GColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(GRadius.lg),
                ),
                child: Text(
                  tr('Waiting to upload: your save from {0} isn\'t on RomM yet. It goes up when RomM can be reached.', [
                    formatSaveTime(waiting.first.timestamp),
                  ]),
                  style: const TextStyle(color: GColors.accent),
                ),
              ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _segment(tr('Saves {0}', [count]), !_states, () => setState(() => _states = false)),
                      _segment(
                        tr('States {0}', [states.where((s) => s.owner == null).length]),
                        _states,
                        () => setState(() => _states = true),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _button(
                  tr('Upload to RomM'),
                  Icons.upload,
                  who == null ? null : () async => _say(await actions.upload(_game, who), tr('Uploaded to RomM.')),
                ),
                _button(
                  tr('Back up now'),
                  Icons.add,
                  who == null
                      ? null
                      : () async => _say(await actions.backUpNow(_game, who), tr('Backed up on this PC.')),
                ),
              ],
            ),
            const SizedBox(height: GSpace.s2),
            if (!_states && who != null && unclaimed.isNotEmpty) _unclaimed(who, unclaimed),
            Expanded(
              child: _states
                  ? StateList(
                      states: states,
                      chosen: null,
                      onChoose: _stateMenu,
                      loading: statesAsync.isLoading,
                      onShare: (s) => _share(stateId: s.remoteId, shared: !s.shared),
                      onDelete: _deleteState,
                    )
                  : SaveList(
                      view: view,
                      mode: SaveListMode.manage,
                      nameOf: menu.nameOf,
                      onRestore: (s) => _restore(menu, view, s),
                      onDelete: _delete,
                      onShare: (s) => _share(saveId: s.rommSave?['id'] as int?, shared: !s.shared),
                      footer: const SizedBox(height: GSpace.s14),
                    ),
            ),
          ],
        );
      },
    );
  }
}
