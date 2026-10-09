import 'package:flutter/material.dart';

import '../../../core/save/catalog/save_maker.dart';
import '../../../play/play_menu.dart';
import '../../theme/tokens.dart';
import '../../widgets/g_dropdown.dart';
import '../../widgets/g_focusable.dart';

/// The play screen's "⚙ Plays in" (spec Part 4), as RomM's settings: the
/// emulator and RetroArch's core as dropdowns, Full screen, Always for this
/// game, and how many saves the emulator can't use with Show all.
/// [compact]: one row above the list (narrow windows).
class PlaySettingsPanel extends StatelessWidget {
  const PlaySettingsPanel({
    super.key,
    required this.menu,
    required this.picked,
    required this.remember,
    required this.hidden,
    required this.showAll,
    required this.onPickEmulator,
    required this.onPickCore,
    required this.onRemember,
    required this.onShowAll,
    required this.onFullscreen,
    required this.emulatorField,
    required this.coreField,
    this.fullscreen,
    this.openField,
    this.compact = false,
  });

  final PlayMenu menu;
  final SaveMaker picked;
  final bool remember;
  final int hidden;
  final bool showAll;
  final VoidCallback onPickEmulator;
  final VoidCallback onPickCore;
  final ValueChanged<bool> onRemember;
  final VoidCallback onShowAll;
  final ValueChanged<bool> onFullscreen;

  /// Where the dropdowns open their lists.
  final GlobalKey emulatorField;
  final GlobalKey coreField;

  /// The picked emulator's Full screen; null when Gargosy can't set it.
  final bool? fullscreen;

  /// 'emulator' or 'core' while its list is open (the chevron points up).
  final String? openField;
  final bool compact;

  Widget _always() => GFocusable(
        key: const ValueKey('play-always'),
        borderRadius: GRadius.pill,
        onActivate: () => onRemember(!remember),
        child: Padding(
          padding: const EdgeInsets.all(GSpace.s2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(remember ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: GColors.fgSecondary),
            const SizedBox(width: GSpace.s2),
            const Flexible(child: Text('Always for this game', style: TextStyle(color: GColors.fgSecondary))),
          ]),
        ),
      );

  Widget _fullscreen() {
    final on = fullscreen;
    return GFocusable(
      key: const ValueKey('play-fullscreen'),
      borderRadius: GRadius.pill,
      onActivate: on == null ? null : () => onFullscreen(!on),
      child: Opacity(
        opacity: on == null ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.all(GSpace.s1),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(
              value: on ?? false,
              onChanged: on == null ? null : onFullscreen,
              activeThumbColor: GColors.fg,
              activeTrackColor: GColors.primary,
            ),
            const SizedBox(width: GSpace.s2),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Full screen',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: on == true ? GColors.primaryHover : GColors.fgSecondary)),
                if (on == null)
                  const Text('Set in the emulator', style: TextStyle(fontSize: GFont.sm, color: GColors.fgMuted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final option = menu.optionOf(picked);
    final hasCores = option != null && option.cores.isNotEmpty;
    final emulator = KeyedSubtree(
      key: emulatorField,
      child: GDropdownField(
        key: const ValueKey('play-emulator'),
        icon: Icons.sports_esports_outlined,
        text: option?.name ?? picked.emulatorId,
        onPress: onPickEmulator,
        open: openField == 'emulator',
        compact: compact,
      ),
    );
    final core = KeyedSubtree(
      key: coreField,
      child: GDropdownField(
        key: const ValueKey('play-core'),
        icon: Icons.memory,
        text: hasCores ? 'Core: ${option.coreName(picked.coreId)}' : 'Core: RetroArch only',
        onPress: hasCores ? onPickCore : null,
        open: openField == 'core',
        compact: compact,
      ),
    );
    final hiddenNote = hidden == 0 && !showAll
        ? null
        : GFocusable(
            borderRadius: GRadius.pill,
            onActivate: onShowAll,
            child: Padding(
              padding: const EdgeInsets.all(GSpace.s2),
              child: Text(
                  showAll
                      ? 'Hide the saves ${menu.nameOf(picked)} can\'t use'
                      : '$hidden ${hidden == 1 ? 'save is' : 'saves are'} hidden: ${menu.nameOf(picked)} can\'t use '
                          '${hidden == 1 ? 'it' : 'them'}. Show all',
                  style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted)),
            ),
          );
    if (compact) {
      return Wrap(
        key: const ValueKey('play-settings'),
        spacing: GSpace.s2,
        runSpacing: GSpace.s2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [emulator, if (hasCores) core, _fullscreen(), _always(), ?hiddenNote],
      );
    }
    return Container(
      key: const ValueKey('play-settings'),
      padding: const EdgeInsets.all(GSpace.s4),
      decoration: BoxDecoration(color: GColors.bgElevated, borderRadius: BorderRadius.circular(GRadius.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Row(children: [
          Icon(Icons.settings, size: 16, color: GColors.fgMuted),
          SizedBox(width: GSpace.s2),
          Text('PLAYS IN',
              style: TextStyle(
                  fontSize: GFont.sm, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: GColors.fgMuted)),
        ]),
        const SizedBox(height: GSpace.s3),
        emulator,
        const SizedBox(height: GSpace.s3),
        core,
        const SizedBox(height: GSpace.s3),
        Align(alignment: Alignment.centerLeft, child: _fullscreen()),
        Align(alignment: Alignment.centerLeft, child: _always()),
        if (hiddenNote != null) ...[const SizedBox(height: GSpace.s2), hiddenNote],
      ]),
    );
  }
}
