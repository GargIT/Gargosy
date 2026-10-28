import 'package:flutter/material.dart';

import '../../../core/save/catalog/play_choice.dart';
import '../../../core/save/resume_service.dart';
import '../../../core/save/save_state_info.dart';
import '../../theme/tokens.dart';
import '../../../core/save/catalog/save_entry.dart' show SaveOwner;
import '../g_focusable.dart';
import 'player_avatar.dart';
import 'save_list.dart';
import 'save_row.dart';
import 'save_labels.dart';
import '../../../l10n/tr.dart';

/// The play screen's save states: newest first, with where each one is.
/// A chooses one; Start resumes it in the emulator that made it. Other
/// players' shared states (#92) follow under From other players, by player,
/// two players a row when there's room.
class StateList extends StatelessWidget {
  const StateList({
    super.key,
    required this.states,
    required this.chosen,
    required this.onChoose,
    required this.loading,
    this.onShare,
    this.onDelete,
  });

  final List<ResumeEntry> states;
  final PlayItem? chosen;
  final void Function(ResumeEntry entry) onChoose;

  /// RomM's states are still being read.
  final bool loading;

  /// Y on the player's own state on RomM (#92): share it, or stop
  /// ([ResumeEntry.shared] tells which).
  final void Function(ResumeEntry entry)? onShare;

  /// Hold A on the player's own state (#94): delete it, on this PC and on
  /// RomM.
  final void Function(ResumeEntry entry)? onDelete;

  static String _where(ResumeEntry e) => switch (e.where) {
    _ when e.owner != null => tr('on RomM'),
    ResumeWhere.thisPc => tr('on this PC'),
    ResumeWhere.romm => tr('on RomM'),
    ResumeWhere.both => e.newerOnRomm ? tr('newer on RomM') : tr('on this PC and RomM'),
  };

  Widget _row(ResumeEntry e) {
    final mine = chosen is StatePlay && (chosen as StatePlay).entry == e;
    return Padding(
      padding: const EdgeInsets.only(bottom: GSpace.s2),
      child: GFocusable(
        borderRadius: GRadius.lg,
        // A state the emulator can't start in is shown, not chosen.
        onActivate: e.resumable ? () => onChoose(e) : null,
        onFavorite: onShare != null && e.owner == null && e.remoteId != null ? () => onShare!(e) : null,
        onLongActivate: onDelete != null && e.owner == null ? () => onDelete!(e) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
          decoration: BoxDecoration(
            color: mine ? GColors.primary.withValues(alpha: 0.22) : GColors.surface,
            borderRadius: BorderRadius.circular(GRadius.lg),
          ),
          child: Row(
            children: [
              Icon(
                !e.resumable ? Icons.info_outline : (mine ? Icons.radio_button_checked : Icons.radio_button_off),
                color: mine ? GColors.primary : GColors.fgSecondary,
              ),
              const SizedBox(width: GSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(e.slot.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        if (e.shared) SaveRow.tag(tr('shared'), GColors.gargosyTeal),
                      ],
                    ),
                    Text(
                      '${e.emulatorName} · ${formatSaveTime(e.savedAt)} · ${_where(e)}',
                      style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                    ),
                    // Shown here, the resume loads it without asking again
                    // (ResumeService.checkBeforeLaunch: "seen").
                    if (!e.resumable && e.owner != null)
                      Text(
                        tr('{0} can\'t start in this state, so another player\'s can\'t be used here.', [
                          e.emulatorName,
                        ]),
                        style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                      )
                    else if (!e.resumable)
                      Text(
                        tr('Start the game, then load it from {0}\'s menu: {1} can\'t start in a state.', [
                          e.emulatorName,
                          e.emulatorName,
                        ]),
                        style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                      ),
                    if (e.compat == StateCompat.mismatch)
                      Text(
                        tr('Made with {0} {1}; you have {2}. It may not load.', [
                          e.emulatorName,
                          e.emulatorVersion ?? '?',
                          e.installedVersion ?? '?',
                        ]),
                        style: const TextStyle(fontSize: GFont.sm, color: GColors.accent),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _heading(String text, {String? note}) => Padding(
    padding: const EdgeInsets.only(top: GSpace.s3, bottom: GSpace.s2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: GFont.sm,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: GColors.fgMuted,
          ),
        ),
        if (note != null)
          Text(
            note,
            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
          ),
      ],
    ),
  );

  Widget _player(SaveOwner owner, List<ResumeEntry> entries) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: GSpace.s2),
        child: Row(
          children: [
            PlayerAvatar(owner),
            const SizedBox(width: GSpace.s2),
            Text(owner.username, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      ...entries.map(_row),
    ],
  );

  /// From other players: their states by player, two a row when [wide].
  List<Widget> _others(List<ResumeEntry> others, bool wide) {
    final byOwner = <SaveOwner, List<ResumeEntry>>{};
    for (final e in others) {
      byOwner.putIfAbsent(e.owner!, () => []).add(e);
    }
    final players = [for (final e in byOwner.entries) _player(e.key, e.value)];
    return [
      Container(
        key: const ValueKey('state-list-others'),
        margin: const EdgeInsets.only(top: GSpace.s3),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: GColors.border)),
        ),
        child: _heading(
          tr('From other players'),
          note: tr('States others shared on RomM. Resuming one downloads a copy; theirs never changes.'),
        ),
      ),
      if (!wide)
        ...players
      else
        for (var i = 0; i < players.length; i += 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: players[i]),
              const SizedBox(width: GSpace.s6),
              Expanded(child: i + 1 < players.length ? players[i + 1] : const SizedBox.shrink()),
            ],
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final own = [
      for (final s in states)
        if (s.owner == null) s,
    ];
    final others = [
      for (final s in states)
        if (s.owner != null) s,
    ];
    if (states.isEmpty) {
      return Text(
        loading ? tr('Looking for save states…') : tr('No save states yet.'),
        style: const TextStyle(color: GColors.fgMuted),
      );
    }
    return LayoutBuilder(
      builder: (context, c) => ListView(
        children: [
          if (others.isNotEmpty) _heading(tr('Yours')),
          if (own.isEmpty) Text(tr('No save states of yours yet.'), style: const TextStyle(color: GColors.fgMuted)),
          ...own.map(_row),
          if (others.isNotEmpty) ..._others(others, c.maxWidth >= SaveList.twoColumnWidth),
          if (loading)
            Padding(
              padding: const EdgeInsets.only(top: GSpace.s2),
              child: Text(tr('Checking RomM\'s states…'), style: const TextStyle(color: GColors.fgMuted)),
            ),
        ],
      ),
    );
  }
}
