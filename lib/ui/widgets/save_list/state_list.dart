import 'package:flutter/material.dart';

import '../../../core/save/catalog/play_choice.dart';
import '../../../core/save/resume_service.dart';
import '../../../core/save/save_state_info.dart';
import '../../theme/tokens.dart';
import '../g_focusable.dart';
import 'save_labels.dart';

/// The play screen's save states: newest first, with where each one is.
/// A chooses one; Start resumes it in the emulator that made it.
class StateList extends StatelessWidget {
  const StateList({super.key, required this.states, required this.chosen, required this.onChoose, required this.loading});

  final List<ResumeEntry> states;
  final PlayItem? chosen;
  final void Function(ResumeEntry entry) onChoose;

  /// RomM's states are still being read.
  final bool loading;

  static String _where(ResumeEntry e) => switch (e.where) {
        ResumeWhere.thisPc => 'on this PC',
        ResumeWhere.romm => 'on RomM',
        ResumeWhere.both => e.newerOnRomm ? 'newer on RomM' : 'on this PC and RomM',
      };

  Widget _row(ResumeEntry e) {
    final mine = chosen is StatePlay && (chosen as StatePlay).entry == e;
    return Padding(
      padding: const EdgeInsets.only(bottom: GSpace.s2),
      child: GFocusable(
        borderRadius: GRadius.lg,
        onActivate: () => onChoose(e),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
          decoration: BoxDecoration(
            color: mine ? GColors.primary.withValues(alpha: 0.22) : GColors.surface,
            borderRadius: BorderRadius.circular(GRadius.lg),
          ),
          child: Row(children: [
            Icon(mine ? Icons.radio_button_checked : Icons.radio_button_off,
                color: mine ? GColors.primary : GColors.fgSecondary),
            const SizedBox(width: GSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.slot.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${e.emulatorName} · ${formatSaveTime(e.savedAt)} · ${_where(e)}',
                    style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted)),
                // Shown here, the resume loads it without asking again
                // (ResumeService.checkBeforeLaunch: "seen").
                if (e.compat == StateCompat.mismatch)
                  Text(
                      'Made with ${e.emulatorName} ${e.emulatorVersion ?? '?'}; you have ${e.installedVersion ?? '?'}. '
                      'It may not load.',
                      style: const TextStyle(fontSize: GFont.sm, color: GColors.accent)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (states.isEmpty) {
      return Text(loading ? 'Looking for save states…' : 'No save states yet.',
          style: const TextStyle(color: GColors.fgMuted));
    }
    return ListView(children: [
      ...states.map(_row),
      if (loading)
        const Padding(
          padding: EdgeInsets.only(top: GSpace.s2),
          child: Text("Checking RomM's states…", style: TextStyle(color: GColors.fgMuted)),
        ),
    ]);
  }
}
