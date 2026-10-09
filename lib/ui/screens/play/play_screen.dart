import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/gamepad_service.dart';
import '../../../core/romm/romm_models.dart';
import '../../../core/save/catalog/play_choice.dart';
import '../../../core/save/catalog/play_request.dart';
import '../../../core/save/catalog/play_view.dart';
import '../../../core/save/catalog/save_entry.dart';
import '../../../core/save/catalog/save_fit.dart';
import '../../../core/save/catalog/save_maker.dart';
import '../../../core/save/resume_service.dart';
import '../../../play/play_controller.dart';
import '../../../play/play_menu.dart';
import '../../../providers/library_providers.dart';
import '../../input/gargosy_intents.dart';
import '../../shell/backdrop.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/hint_bar.dart';
import '../../widgets/save_labels.dart';
import '../../widgets/toast.dart';
import 'save_rows.dart';
import 'state_rows.dart';

/// Choose the save and emulator a game starts with (spec §7), after
/// Freegosy's play screen in the v2 style. The newest save that fits is
/// chosen already; Start (X, or the button) plays it.
class PlayScreen extends ConsumerStatefulWidget {
  const PlayScreen({super.key, required this.game, this.onNotice});
  final Game game;

  /// Hears what the player should know once the screen has closed (a save
  /// that couldn't be pulled).
  final void Function(String message)? onNotice;

  @override
  ConsumerState<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends ConsumerState<PlayScreen> {
  bool _pickRead = false;
  SaveMaker? _picked;
  bool _remember = false;
  bool _showAll = false;
  PlayItem? _chosen;
  bool _starting = false;

  /// 0 saves, 1 states; null: the tab of what is chosen.
  int? _tab;

  PlayMenuKey get _key => PlayMenuKey(widget.game);

  @override
  void initState() {
    super.initState();
    // RomM's saves are read fresh each time the screen opens.
    Future.microtask(() {
      if (!mounted) return;
      ref.invalidate(playMenuProvider(_key));
      ref.invalidate(playStatesProvider(_key));
    });
  }

  void _readPick(PlayMenu menu) {
    if (_pickRead) return;
    _pickRead = true;
    _picked = menu.forThisGame;
    _remember = menu.remembered != null;
  }

  PlayView _view(PlayMenu menu, List<ResumeEntry> states) => buildPlayView(
        catalog: menu.catalog,
        states: states,
        platformSlug: widget.game.platformSlug ?? '',
        picked: _picked,
        platformDefault: menu.platformDefault,
        installed: menu.installedIds,
        showAll: _showAll,
      );

  Future<void> _pickEmulator(PlayMenu menu) async {
    if (menu.emulators.isEmpty) return;
    final current = menu.emulators.indexWhere((e) => e.maker == _picked);
    final i = await showChoice(context,
        title: 'Play ${widget.game.displayName} in', labels: [for (final e in menu.emulators) e.name], current: current < 0 ? null : current);
    if (i == null || !mounted) return;
    setState(() {
      _picked = menu.emulators[i].maker;
      _remember = _picked == menu.remembered;
      _chosen = null;
    });
  }

  static String _sourceLabel(SaveEntry e) => switch (e.source) {
        SaveSource.local => 'save on this PC',
        SaveSource.backup => 'backup',
        SaveSource.romm => 'RomM save',
      };

  Future<bool> _confirm(PlayPrompt prompt, PlayItem chosen, PlayView view, PlayMenu menu) {
    if (chosen is StatePlay) {
      return showConfirm(context,
          title: 'Resume an older state?',
          body: 'This state is from ${formatSaveTime(chosen.entry.savedAt)}, but your save is from '
              '${formatSaveTime(view.newestSave!)}. Resuming may roll your save back.',
          yes: 'Resume anyway',
          focusYes: false);
    }
    final item = chosen as SavePlay;
    final target = item.fit.playsIn!;
    final name = menu.nameOf(target);
    final (title, body) = switch (prompt) {
      PlayPrompt.olderSave => (
          'Play an older save?',
          'This replaces your $name save from ${formatSaveTime(view.newestLocalFor(target)!)} with the '
              '${_sourceLabel(item.entry)} from ${formatSaveTime(item.entry.savedAt)}'
              '${item.fit.kind == SaveFitKind.converted ? ', converted for $name' : ''}.\n\n'
              'Your current save is backed up first, so you can get it back.',
        ),
      PlayPrompt.notOnRomm => (
          "Your save on this PC isn't on RomM",
          'Your $name save on this PC changed since its last upload (played offline?). Playing the '
              '${_sourceLabel(item.entry)} from ${formatSaveTime(item.entry.savedAt)} replaces it.\n\n'
              'A backup of it is kept on this PC.',
        ),
      PlayPrompt.olderState => ('Resume an older state?', 'Resuming may roll your save back.'),
    };
    return showConfirm(context, title: title, body: body, yes: 'Replace and play', focusYes: false);
  }

  /// RomM's copy of the save on this PC [entry] (same content or the RomM
  /// save it was last synced with): RomM is told this device has it.
  static Map<String, dynamic>? _rommCopyOf(SaveEntry entry, PlayView view) {
    for (final g in view.romm) {
      for (final r in [g.newest, ...g.older]) {
        final save = r.entry.rommSave;
        if (!r.sameAsLocal || save == null) continue;
        final hash = save['content_hash']?.toString();
        if ((hash != null && entry.contentHashes.contains(hash)) || save['id']?.toString() == entry.sameAsRommId) return save;
      }
    }
    return null;
  }

  Future<bool> _confirmVersion(ResumeEntry entry, String stateVersion, String installed) => showConfirm(context,
      title: 'Load a state from another version?',
      body: '${entry.slot.label} was made by ${entry.emulatorName} $stateVersion; you have $installed. '
          'It may not load, or the game may misbehave.',
      yes: 'Load it',
      focusYes: false);

  Future<void> _resume(ResumeEntry entry) async {
    setState(() => _starting = true);
    try {
      final reason = await ref.read(playControllerProvider.notifier).resume(widget.game, entry,
          confirmVersion: (v, i) => _confirmVersion(entry, v, i), onNotice: widget.onNotice);
      if (!mounted) return;
      if (reason != null) {
        showToast(context, reason);
      } else {
        Navigator.of(context).maybePop();
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _start(PlayMenu menu, PlayView view) async {
    if (_starting) return;
    final item = _chosen ?? view.preselected;
    if (item != null) {
      final prompt = view.promptFor(item);
      if (prompt != null && !await _confirm(prompt, item, view, menu)) return;
      if (!mounted) return;
    }
    if (item is StatePlay) return _resume(item.entry);
    final save = item is SavePlay ? item : null;
    final emulator = save?.fit.playsIn ?? _picked;
    if (emulator == null || !mounted) return;
    final forget = !_remember && _picked != null && _picked == menu.remembered;
    final own = save != null && save.entry.source == SaveSource.local && save.entry.maker == emulator;
    final request = PlayRequest(
      emulator: emulator,
      save: save == null || own ? null : save.entry,
      remember: _remember && _picked == emulator,
      forget: forget,
      rommCopy: save != null && save.entry.source == SaveSource.local ? _rommCopyOf(save.entry, view) : null,
    );
    setState(() => _starting = true);
    try {
      final reason = await ref.read(playControllerProvider.notifier).play(widget.game, request: request, onNotice: widget.onNotice);
      if (!mounted) return;
      if (reason != null) {
        showToast(context, reason);
      } else {
        Navigator.of(context).maybePop();
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Widget _emulatorRow(PlayMenu menu) {
    final picked = _picked;
    if (picked == null) {
      return Text('No emulator for ${widget.game.platformDisplayName ?? 'this platform'} is installed. '
          'Install one under Emulators (Start → Emulators).', style: const TextStyle(color: GColors.fgSecondary));
    }
    return Row(children: [
      Flexible(
        child: GFocusable(
          borderRadius: GRadius.pill,
          onActivate: () => _pickEmulator(menu),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
            decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
            child: Text('Plays in ${menu.nameOf(picked)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ),
      const SizedBox(width: GSpace.s3),
      GFocusable(
        borderRadius: GRadius.pill,
        onActivate: () => setState(() => _remember = !_remember),
        child: Padding(
          padding: const EdgeInsets.all(GSpace.s2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_remember ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: GColors.fgSecondary),
            const SizedBox(width: GSpace.s2),
            const Text('Always for this game', style: TextStyle(color: GColors.fgSecondary)),
          ]),
        ),
      ),
    ]);
  }

  Widget _tabButton(String label, int index, int current) => GFocusable(
        borderRadius: GRadius.pill,
        onActivate: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
          decoration: BoxDecoration(
            color: index == current ? GColors.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(GRadius.pill),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: index == current ? GColors.fg : GColors.fgSecondary)),
        ),
      );

  Widget _body(PlayMenu menu) {
    _readPick(menu);
    final statesAsync = ref.watch(playStatesProvider(_key));
    final states = statesAsync.valueOrNull ?? const <ResumeEntry>[];
    final view = _view(menu, states);
    final chosen = _chosen ?? view.preselected;
    final tab = _tab ?? (chosen is StatePlay ? 1 : 0);
    final startLabel = switch (chosen) {
      SavePlay(:final entry) => 'Start with the ${_sourceLabel(entry)}',
      StatePlay(:final entry) => 'Resume ${entry.slot.label}',
      _ => _picked == null ? 'Start' : 'Start without a save',
    };
    return Actions(
      actions: {
        FavoriteIntent: CallbackAction<FavoriteIntent>(onInvoke: (_) => _pickEmulator(menu)),
        DetailIntent: CallbackAction<DetailIntent>(onInvoke: (_) => _start(menu, view)),
        PrevTabIntent: CallbackAction<PrevTabIntent>(onInvoke: (_) => setState(() => _tab = 0)),
        NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) => setState(() => _tab = 1)),
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _emulatorRow(menu),
        const SizedBox(height: GSpace.s4),
        Row(children: [
          _tabButton('Saves', 0, tab),
          const SizedBox(width: GSpace.s2),
          _tabButton(view.states.isEmpty ? 'States' : 'States (${view.states.length})', 1, tab),
        ]),
        const SizedBox(height: GSpace.s3),
        Expanded(
          child: tab == 0
              ? SaveRows(
                  view: view,
                  chosen: chosen,
                  nameOf: menu.nameOf,
                  onChoose: (row) => setState(() => _chosen = row.item),
                  onShowAll: view.hidden == 0 ? null : () => setState(() => _showAll = !_showAll),
                  showAll: _showAll,
                )
              : StateRows(
                  states: view.states,
                  chosen: chosen,
                  loading: statesAsync.isLoading,
                  onChoose: (e) => setState(() => _chosen = StatePlay(e)),
                ),
        ),
        const SizedBox(height: GSpace.s4),
        GFocusable(
          key: const ValueKey('play-start'),
          autofocus: true,
          borderRadius: GRadius.pill,
          onActivate: _picked == null && chosen == null ? null : () => _start(menu, view),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: GSpace.s6, vertical: GSpace.s3),
            decoration: BoxDecoration(color: GColors.primary, borderRadius: BorderRadius.circular(GRadius.pill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.play_arrow),
              const SizedBox(width: GSpace.s2),
              Text(_starting ? 'Starting…' : startLabel,
                  style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(playMenuProvider(_key));
    final game = widget.game;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Backdrop(
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s10, GSpace.rowPad, GSpace.s4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CoverImage(url: coverUrlFor(ref, game), title: game.displayName, width: 200, height: 270),
                const SizedBox(width: GSpace.s8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(game.displayName, style: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800)),
                    Text(game.platformDisplayName ?? '', style: const TextStyle(color: GColors.fgSecondary)),
                    const SizedBox(height: GSpace.s5),
                    Expanded(
                      child: menu.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => ErrorRetry(message: '$e', onRetry: () => ref.invalidate(playMenuProvider(_key))),
                        data: (m) => m == null ? const SizedBox.shrink() : _body(m),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          const HintBar(hints: [
            Hint(GameAction.confirm, 'Choose'),
            Hint(GameAction.detail, 'Start'),
            Hint(GameAction.favorite, 'Emulator'),
            Hint(GameAction.l1, 'Saves'),
            Hint(GameAction.r1, 'States'),
            Hint(GameAction.back, 'Back'),
          ]),
        ]),
      ),
    );
  }
}
