import 'package:flutter/material.dart';

import '../../../core/save/catalog/play_view.dart';
import '../../../core/save/catalog/save_entry.dart';
import '../../../core/save/catalog/save_fit.dart';
import '../../../core/save/catalog/save_maker.dart';
import '../../theme/tokens.dart';
import '../g_focusable.dart';
import 'save_labels.dart';

/// One save in the list: its name, when and how big, the emulator that made
/// it (orange), whether RomM has it (green), whether it's converted to the
/// chosen emulator; greyed with the reason when that emulator can't use it.
class SaveRow extends StatelessWidget {
  const SaveRow({
    super.key,
    required this.row,
    required this.nameOf,
    this.chosen = false,
    this.onRomm = false,
    this.showChoice = true,
    this.onActivate,
    this.onDetail,
    this.onLongActivate,
    this.onFavorite,
  });

  final PlayRow row;
  final String Function(SaveMaker) nameOf;
  final bool chosen;
  final bool onRomm;

  /// The radio mark (choose mode).
  final bool showChoice;
  final VoidCallback? onActivate;
  final VoidCallback? onDetail;
  final VoidCallback? onLongActivate;

  /// Y (#92): share the player's own RomM save, or stop.
  final VoidCallback? onFavorite;

  static Widget tag(String text, Color color) => Container(
    margin: const EdgeInsets.only(left: GSpace.s2),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(GRadius.sm),
      border: Border.all(color: color.withValues(alpha: 0.6)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: GFont.xs, color: color),
    ),
  );

  String _detail() {
    final e = row.entry;
    final fit = row.fit;
    return [
      if (e.source == SaveSource.romm && e.slot != null) 'slot ${e.slot}',
      formatSaveTime(e.savedAt),
      if (e.sizeBytes != null) formatSaveSize(e.sizeBytes!),
      if (!fit.usable) fit.reason ?? "can't be played here",
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final e = row.entry;
    final usable = row.fit.usable;
    final maker = e.tag ?? e.maker?.emulatorId;
    return Padding(
      padding: const EdgeInsets.only(bottom: GSpace.s2),
      child: GFocusable(
        key: ValueKey(!usable ? 'save-row-unusable' : (chosen ? 'save-row-chosen' : 'save-row')),
        borderRadius: GRadius.lg,
        onActivate: onActivate,
        onDetail: onDetail,
        onLongActivate: onLongActivate,
        onFavorite: onFavorite,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
          decoration: BoxDecoration(
            color: chosen ? GColors.primary.withValues(alpha: 0.22) : GColors.surface,
            borderRadius: BorderRadius.circular(GRadius.lg),
          ),
          child: Opacity(
            opacity: usable ? 1 : 0.45,
            child: Row(
              children: [
                if (showChoice) ...[
                  Icon(
                    chosen ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 18,
                    color: chosen ? GColors.primary : GColors.fgSecondary,
                  ),
                  const SizedBox(width: GSpace.s3),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.fileName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _detail(),
                        style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                      ),
                    ],
                  ),
                ),
                if (maker != null && maker.isNotEmpty) tag(maker, GColors.accent),
                if (row.fit.kind == SaveFitKind.converted) tag('converted', GColors.primary),
                if (onRomm) tag('on RomM', GColors.success),
                if (e.shared) tag('shared', GColors.gargosyTeal),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
