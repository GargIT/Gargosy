import '../game/game_screen.dart';
import '../../../play/play_engine.dart';
import '../../widgets/g_dropdown.dart';
import '../../widgets/game_transition.dart';
import '../../widgets/outlined_back_button.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/gamepad_service.dart';
import '../../../core/romm/romm_models.dart';
import '../../../core/save/catalog/play_choice.dart';
import '../../../core/save/catalog/save_count.dart';
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
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/hint_bar.dart';
import '../../widgets/save_list/save_labels.dart';
import '../../widgets/save_list/save_list.dart';
import '../../widgets/save_list/state_list.dart';
import '../../widgets/toast.dart';
import 'play_settings_panel.dart';

/// Choose the save or state and the emulator a game starts with (spec Part
/// 4), after Freegosy's play screen in the v2 style: the cover and the main
/// button on the left, the saves in the middle, "⚙ Plays in" on the right
/// (one row above the list in narrow windows). The newest save or state is
/// chosen already; A on the main button plays it.
class PlayScreen extends ConsumerStatefulWidget {
  const PlayScreen({super.key, required this.game, this.onNotice});
  final Game game;

  /// Hears what the player should know once the screen has closed (a save
  /// that couldn't be pulled).
  final void Function(String message)? onNotice;

  /// The window width from which the settings get their own panel.
  static const wideWidth = 1100.0;

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

  /// Where the emulator and core lists open, and which one is open.
  final _emulatorField = GlobalKey();
  final _coreField = GlobalKey();
  String? _openField;

  /// Full screen as changed here, per emulator (the menu has what it was).
  final _fullscreen = <String, bool>{};

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
    final current = menu.emulators.indexWhere((e) => e.maker.emulatorId == _picked?.emulatorId);
    final i = await _dropdown('emulator', _emulatorField, [for (final e in menu.emulators) e.name], current);
    if (i == null || !mounted) return;
    final option = menu.emulators[i].maker;
    // The same emulator keeps its core; the remembered emulator comes back
    // with its remembered core; another gets the platform's core.
    if (option.emulatorId == _picked?.emulatorId) return;
    final remembered = menu.remembered;
    setState(() {
      _picked = remembered != null && remembered.emulatorId == option.emulatorId ? remembered : option;
      _remember = _picked?.emulatorId == remembered?.emulatorId;
      _chosen = null;
    });
  }

  Future<void> _pickCore(PlayMenu menu) async {
    final option = _picked == null ? null : menu.optionOf(_picked!);
    if (option == null || option.cores.isEmpty) return;
    final current = option.cores.indexWhere((c) => bareCoreId(c.id) == _picked?.coreId);
    final i = await _dropdown('core', _coreField, [for (final c in option.cores) c.displayName], current);
    if (i == null || !mounted) return;
    setState(() {
      _picked = SaveMaker(option.maker.emulatorId, coreId: bareCoreId(option.cores[i].id));
      _chosen = null;
    });
  }

  Future<int?> _dropdown(String name, GlobalKey field, List<String> labels, int current) async {
    setState(() => _openField = name);
    final i = await showDropdown(context, field: field, labels: labels, current: current < 0 ? null : current);
    if (mounted) setState(() => _openField = null);
    return i;
  }

  bool? _fullscreenOf(PlayMenu menu, SaveMaker picked) {
    final saved = menu.optionOf(picked)?.fullscreen;
    return saved == null ? null : _fullscreen[picked.emulatorId] ?? saved;
  }

  Future<void> _setFullscreen(String emulatorId, bool on) async {
    setState(() => _fullscreen[emulatorId] = on);
    await ref.read(playEngineProvider)?.setFullscreen(emulatorId, on);
  }

  static String _sourceLabel(SaveEntry e) => switch (e.source) {
    SaveSource.local => 'save on this PC',
    SaveSource.backup => 'backup',
    SaveSource.romm => 'RomM save',
  };

  Future<bool> _confirm(PlayPrompt prompt, PlayItem chosen, PlayView view, PlayMenu menu) {
    if (chosen is StatePlay) {
      return showConfirm(
        context,
        title: 'Resume an older state?',
        body:
            'This state is from ${formatSaveTime(chosen.entry.savedAt)}, but your save is from '
            '${formatSaveTime(view.newestSave!)}. Resuming may roll your save back.',
        yes: 'Resume anyway',
        focusYes: false,
      );
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
        if ((hash != null && entry.contentHashes.contains(hash)) || save['id']?.toString() == entry.sameAsRommId) {
          return save;
        }
      }
    }
    return null;
  }

  Future<bool> _confirmVersion(ResumeEntry entry, String stateVersion, String installed) => showConfirm(
    context,
    title: 'Load a state from another version?',
    body:
        '${entry.slot.label} was made by ${entry.emulatorName} $stateVersion; you have $installed. '
        'It may not load, or the game may misbehave.',
    yes: 'Load it',
    focusYes: false,
  );

  Future<void> _finish(Future<String?> Function() start) async {
    setState(() => _starting = true);
    try {
      final reason = await start();
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
    if (item is StatePlay) {
      final entry = item.entry;
      return _finish(
        () => ref
            .read(playControllerProvider.notifier)
            .resume(
              widget.game,
              entry,
              confirmVersion: (v, i) => _confirmVersion(entry, v, i),
              onNotice: widget.onNotice,
            ),
      );
    }
    final save = item is SavePlay ? item : null;
    final emulator = save?.fit.playsIn ?? _picked;
    if (emulator == null || !mounted) return;
    final forget = !_remember && _picked != null && _picked?.emulatorId == menu.remembered?.emulatorId;
    final own = save != null && save.entry.source == SaveSource.local && save.entry.maker == emulator;
    final request = PlayRequest(
      emulator: emulator,
      save: save == null || own ? null : save.entry,
      remember: _remember && _picked?.emulatorId == emulator.emulatorId,
      forget: forget,
      rommCopy: save != null && save.entry.source == SaveSource.local ? _rommCopyOf(save.entry, view) : null,
    );
    return _finish(
      () => ref.read(playControllerProvider.notifier).play(widget.game, request: request, onNotice: widget.onNotice),
    );
  }

  /// What A does, in one line under the main button.
  String _whatA(PlayMenu menu, PlayItem? chosen) => switch (chosen) {
    SavePlay(:final entry, :final fit) =>
      'in ${menu.nameOf(fit.playsIn ?? _picked!)} · ${_sourceLabel(entry)}, ${formatSaveTime(entry.savedAt)}',
    StatePlay(:final entry) => '${entry.slot.label} in ${entry.emulatorName} · ${formatSaveTime(entry.savedAt)}',
    _ => _picked == null ? '' : 'in ${menu.nameOf(_picked!)} · starts without a save',
  };

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

  /// The game page's cover column, in the same place: the cover, the main
  /// button and what A does; Back at the bottom, outlined.
  Widget _left(PlayMenu menu, PlayView view, PlayItem? chosen) {
    final game = widget.game;
    final resume = chosen is StatePlay;
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          coverHero(
            game,
            SizedBox(
              key: const ValueKey('play-cover'),
              width: 240,
              height: 324,
              child: CoverImage(url: coverUrlFor(ref, game), title: game.displayName, width: 240, height: 324),
            ),
          ),
          const SizedBox(height: GSpace.s5),
          GFocusable(
            key: const ValueKey('play-start'),
            autofocus: true,
            borderRadius: GRadius.pill,
            onActivate: _picked == null && chosen == null ? null : () => _start(menu, view),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: GSpace.s3),
              decoration: BoxDecoration(color: GColors.primary, borderRadius: BorderRadius.circular(GRadius.pill)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(resume ? Icons.replay : Icons.play_arrow),
                  const SizedBox(width: GSpace.s2),
                  Text(
                    _starting ? 'Starting…' : (resume ? 'Resume' : 'Play'),
                    style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: GSpace.s2),
          Text(
            // While the ROM is readied (a zip unpacked, an Xbox disc
            // converted), how far it is; else what A does.
            ref.watch(playControllerProvider.select((s) => s.runningGameId == widget.game.id ? s.preparing : null)) ??
                _whatA(menu, chosen),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
          ),
          const Spacer(),
          const OutlinedBackButton(key: ValueKey('play-back'), label: 'Back to the game'),
          const SizedBox(height: GSpace.s4),
        ],
      ),
    );
  }

  Widget _body(PlayMenu menu, bool wide) {
    _readPick(menu);
    final statesAsync = ref.watch(playStatesProvider(_key));
    final states = statesAsync.valueOrNull ?? const <ResumeEntry>[];
    final view = _view(menu, states);
    final chosen = _chosen ?? view.preselected;
    final tab = _tab ?? (chosen is StatePlay ? 1 : 0);
    final picked = _picked;
    final panel = picked == null
        ? Text(
            'No emulator for ${widget.game.platformDisplayName ?? 'this platform'} is installed. '
            'Install one under Emulators (Start → Emulators).',
            style: const TextStyle(color: GColors.fgSecondary),
          )
        : PlaySettingsPanel(
            menu: menu,
            picked: picked,
            remember: _remember,
            hidden: view.hidden,
            showAll: _showAll,
            compact: !wide,
            onPickEmulator: () => _pickEmulator(menu),
            onPickCore: () => _pickCore(menu),
            onRemember: (on) => setState(() => _remember = on),
            onShowAll: () => setState(() => _showAll = !_showAll),
            emulatorField: _emulatorField,
            coreField: _coreField,
            openField: _openField,
            fullscreen: _fullscreenOf(menu, picked),
            onFullscreen: (on) => _setFullscreen(picked.emulatorId, on),
          );
    final middle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!wide) ...[panel, const SizedBox(height: GSpace.s3)],
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _segment(
                'Saves ${distinctSaveCount([for (final r in view.saveRows) r.entry])}',
                tab == 0,
                () => setState(() => _tab = 0),
              ),
              _segment('States ${view.states.length}', tab == 1, () => setState(() => _tab = 1)),
            ],
          ),
        ),
        const SizedBox(height: GSpace.s2),
        Expanded(
          child: tab == 0
              ? SaveList(
                  view: view,
                  mode: SaveListMode.choose,
                  nameOf: menu.nameOf,
                  chosen: chosen,
                  onChoose: (s) => setState(() => _chosen = s),
                )
              : StateList(
                  states: view.states,
                  chosen: chosen,
                  loading: statesAsync.isLoading,
                  onChoose: (e) => setState(() => _chosen = StatePlay(e)),
                ),
        ),
      ],
    );
    return Actions(
      actions: {
        FavoriteIntent: CallbackAction<FavoriteIntent>(onInvoke: (_) => _pickEmulator(menu)),
        PrevTabIntent: CallbackAction<PrevTabIntent>(onInvoke: (_) => setState(() => _tab = 0)),
        NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) => setState(() => _tab = 1)),
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _left(menu, view, chosen),
          const SizedBox(width: GSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // As on the game page, so the move between the two is smooth.
                GameScreen.titleBlock(widget.game),
                const SizedBox(height: GSpace.s5),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: middle),
                      if (wide) ...[const SizedBox(width: GSpace.s6), SizedBox(width: 260, child: panel)],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(playMenuProvider(_key));
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GameArtBackdrop(
        game: widget.game,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: GameScreen.padding,
                child: LayoutBuilder(
                  builder: (context, c) => menu.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ErrorRetry(message: '$e', onRetry: () => ref.invalidate(playMenuProvider(_key))),
                    data: (m) => m == null ? const SizedBox.shrink() : _body(m, c.maxWidth >= PlayScreen.wideWidth),
                  ),
                ),
              ),
            ),
            const HintBar(
              hints: [
                Hint(GameAction.confirm, 'Choose / Play'),
                Hint(GameAction.l1, 'Saves'),
                Hint(GameAction.r1, 'States'),
                Hint(GameAction.favorite, 'Emulator'),
                Hint(GameAction.detail, 'Fold'),
                Hint(GameAction.back, 'Back'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
