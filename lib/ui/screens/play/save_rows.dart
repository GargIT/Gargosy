import 'package:flutter/material.dart';

import '../../../core/save/catalog/play_choice.dart';
import '../../../core/save/catalog/play_view.dart';
import '../../../core/save/catalog/save_fit.dart';
import '../../../core/save/catalog/save_maker.dart';
import '../../theme/tokens.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/save_labels.dart';

/// The play screen's saves, in RomM's sections: On this PC, Backups, On
/// RomM. The chosen one is marked; A chooses another.
class SaveRows extends StatelessWidget {
  const SaveRows({
    super.key,
    required this.view,
    required this.chosen,
    required this.nameOf,
    required this.onChoose,
    required this.onShowAll,
    required this.showAll,
  });

  final PlayView view;
  final PlayItem? chosen;
  final String Function(SaveMaker) nameOf;
  final void Function(PlayRow row) onChoose;

  /// Null when no save is hidden.
  final VoidCallback? onShowAll;
  final bool showAll;

  bool _isChosen(PlayRow r) => chosen is SavePlay && (chosen as SavePlay).entry == r.entry;

  String _detail(PlayRow r) {
    final parts = <String>[formatSaveTime(r.entry.savedAt)];
    final size = r.entry.sizeBytes;
    if (size != null) parts.add(formatSaveSize(size));
    final fit = r.fit;
    switch (fit.kind) {
      case SaveFitKind.native || SaveFitKind.unknownMaker:
        if (fit.playsIn != null) parts.add('plays in ${nameOf(fit.playsIn!)}');
      case SaveFitKind.converted:
        parts.add('converted for ${nameOf(fit.playsIn!)}');
      case SaveFitKind.unusable:
        parts.add(fit.reason ?? "can't be played here");
    }
    if (r.sameAsLocal) parts.add('same as on this PC');
    return parts.join(' · ');
  }

  Widget _row(PlayRow r) {
    final mine = _isChosen(r);
    return Padding(
      padding: const EdgeInsets.only(bottom: GSpace.s2),
      child: GFocusable(
        key: ValueKey('save-${r.entry.source.name}-${r.entry.fileName}-${r.entry.savedAt.millisecondsSinceEpoch}'),
        borderRadius: GRadius.lg,
        onActivate: r.fit.usable ? () => onChoose(r) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
          decoration: BoxDecoration(
            color: mine ? GColors.primary.withValues(alpha: 0.22) : GColors.surface,
            borderRadius: BorderRadius.circular(GRadius.lg),
          ),
          child: Row(children: [
            Icon(mine ? Icons.radio_button_checked : Icons.radio_button_off,
                key: mine ? ValueKey('chosen-${r.entry.fileName}') : null,
                color: r.fit.usable ? (mine ? GColors.primary : GColors.fgSecondary) : GColors.fgFaint),
            const SizedBox(width: GSpace.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.entry.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: r.fit.usable ? GColors.fg : GColors.fgFaint)),
                Text(_detail(r), style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: GSpace.s3, bottom: GSpace.s2),
        child: Text(text, style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700, color: GColors.fgSecondary)),
      );

  @override
  Widget build(BuildContext context) {
    final romm = [for (final g in view.romm) ...[g.newest, ...g.older]];
    final children = <Widget>[
      if (view.thisPc.isNotEmpty) ...[_heading('On this PC'), ...view.thisPc.map(_row)],
      if (view.backups.isNotEmpty) ...[_heading('Backups'), ...view.backups.map(_row)],
      if (romm.isNotEmpty) ...[_heading('On RomM'), ...romm.map(_row)],
      if (view.rommOffline)
        const Padding(
          padding: EdgeInsets.only(top: GSpace.s3),
          child: Text("RomM can't be reached, so its saves aren't listed.", style: TextStyle(color: GColors.fgMuted)),
        ),
      if (onShowAll != null)
        Padding(
          padding: const EdgeInsets.only(top: GSpace.s2),
          child: GFocusable(
            borderRadius: GRadius.pill,
            onActivate: onShowAll,
            child: Padding(
              padding: const EdgeInsets.all(GSpace.s2),
              child: Text(showAll ? 'Hide saves for other emulators' : 'Show ${view.hidden} saves for other emulators',
                  style: const TextStyle(color: GColors.fgSecondary)),
            ),
          ),
        ),
    ];
    if (children.isEmpty) {
      return const Text('No saves yet. The game starts fresh.', style: TextStyle(color: GColors.fgMuted));
    }
    return ListView(children: children);
  }
}
