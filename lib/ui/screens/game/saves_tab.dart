import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../core/save/catalog/play_choice.dart';
import '../../../core/save/catalog/play_view.dart';
import '../../../core/save/catalog/save_entry.dart';
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
      final ok = await showConfirm(context,
          title: prompt == PlayPrompt.notOnRomm ? "Your save on this PC isn't on RomM" : 'Put an older save on this PC?',
          body: 'This replaces your ${menu.nameOf(target)} save${older == null ? '' : ' from ${formatSaveTime(older)}'} '
              'with the one from ${formatSaveTime(save.savedAt)}. Your current save is backed up first.',
          yes: 'Put it on this PC',
          focusYes: false);
      if (!ok || !mounted) return;
    }
    final reason = await ref.read(saveActionsProvider).restore(_game, save, target);
    _say(reason, 'The save from ${formatSaveTime(save.savedAt)} is on this PC now.');
  }

  Future<void> _delete(SaveEntry save) async {
    final romm = save.source == SaveSource.romm;
    final ok = await showConfirm(context,
        title: romm ? 'Delete this save from RomM?' : 'Delete this backup?',
        body: romm
            ? '${save.fileName} (${formatSaveTime(save.savedAt)}) is deleted on RomM, for every device.'
            : 'The backup from ${formatSaveTime(save.savedAt)} is deleted from this PC.',
        yes: 'Delete',
        no: 'Keep',
        focusYes: false,
        danger: true);
    if (!ok || !mounted) return;
    final reason = await ref.read(saveActionsProvider).delete(_game, save);
    _say(reason, 'Deleted.');
  }

  Widget _button(String label, IconData icon, VoidCallback? onPress) => Padding(
        padding: const EdgeInsets.only(left: GSpace.s2),
        child: GFocusable(
          borderRadius: GRadius.pill,
          onActivate: onPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
            decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: GColors.fgSecondary),
              const SizedBox(width: GSpace.s2),
              Text(label, style: const TextStyle(color: GColors.fgSecondary, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  Widget _segment(String label, bool on, VoidCallback onPress) => GFocusable(
        borderRadius: GRadius.pill,
        onActivate: onPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
          decoration: BoxDecoration(
              color: on ? GColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(GRadius.pill)),
          child: Text(label, style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(playMenuProvider(_key));
    final statesAsync = ref.watch(playStatesProvider(_key));
    final states = statesAsync.valueOrNull ?? const <ResumeEntry>[];
    final waiting = ref.watch(uploadsWaitingProvider(_game.id));
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
        final count = view.saveRows.length;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (waiting.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: GSpace.s3),
              padding: const EdgeInsets.all(GSpace.s3),
              decoration: BoxDecoration(
                  color: GColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(GRadius.lg)),
              child: Text(
                  'Waiting to upload: your save from ${formatSaveTime(waiting.first.timestamp)} '
                  "isn't on RomM yet. It goes up when RomM can be reached.",
                  style: const TextStyle(color: GColors.accent)),
            ),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _segment('Saves $count', !_states, () => setState(() => _states = false)),
                _segment('States ${states.length}', _states, () => setState(() => _states = true)),
              ]),
            ),
            const Spacer(),
            _button('Upload to RomM', Icons.upload,
                who == null ? null : () async => _say(await actions.upload(_game, who), 'Uploaded to RomM.')),
            _button('Back up now', Icons.add,
                who == null ? null : () async => _say(await actions.backUpNow(_game, who), 'Backed up on this PC.')),
          ]),
          const SizedBox(height: GSpace.s2),
          Expanded(
            child: _states
                ? StateList(states: states, chosen: null, onChoose: (_) {}, loading: statesAsync.isLoading)
                : SaveList(
                    view: view,
                    mode: SaveListMode.manage,
                    nameOf: menu.nameOf,
                    onRestore: (s) => _restore(menu, view, s),
                    onDelete: _delete,
                    footer: const SizedBox(height: GSpace.s14),
                  ),
          ),
        ]);
      },
    );
  }
}
