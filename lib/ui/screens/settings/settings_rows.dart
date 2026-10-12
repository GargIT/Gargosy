import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/g_focusable.dart';

const _titleStyle = TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w700, letterSpacing: 0.9);
const _labelStyle = TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w600, color: GColors.fgSecondary);
const _noteStyle = TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary, height: 1.4);

/// RomM's settings card: an upper-case title bar with an icon (and an
/// optional badge on the right), an optional note, then its rows with a
/// line between them.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.title,
    required this.icon,
    this.trailing,
    this.note,
    this.rowPadding = const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    required this.children,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;
  final String? note;
  final EdgeInsets rowPadding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const line = Divider(height: 1, thickness: 1, color: GColors.border);
    return Container(
      margin: const EdgeInsets.only(bottom: GSpace.s4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: GColors.card,
        borderRadius: BorderRadius.circular(GRadius.md),
        border: Border.all(color: GColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(children: [
              Icon(icon, size: 15),
              const SizedBox(width: GSpace.s3),
              Expanded(child: Text(title.toUpperCase(), style: _titleStyle, overflow: TextOverflow.ellipsis)),
              ?trailing,
            ]),
          ),
        ),
        line,
        if (note != null)
          Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 0), child: Text(note!, style: _noteStyle)),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) line,
          Padding(padding: rowPadding, child: children[i]),
        ],
      ]),
    );
  }
}

/// A labelled value: the label above, the value in a box. With [onActivate]
/// it takes focus and A runs it ([action] says what it does, on the right);
/// without, it is read-only and focus passes it by.
class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.onActivate,
    this.action,
    this.actionIcon,
    this.autofocus = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onActivate;
  final String? action;
  final IconData? actionIcon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final readOnly = onActivate == null;
    final box = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: GColors.field,
        borderRadius: BorderRadius.circular(GRadius.chip),
        border: Border.all(color: readOnly ? GColors.border : GColors.borderStrong),
      ),
      child: Row(children: [
        Expanded(
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: GFont.md, color: readOnly ? GColors.fgSecondary : GColors.fg)),
        ),
        if (actionIcon != null) ...[const SizedBox(width: GSpace.s2), Icon(actionIcon, size: 15)],
        if (action != null) ...[
          const SizedBox(width: 6),
          Text(action!, style: const TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w700)),
        ],
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      // The label is clickable too, like the box.
      GestureDetector(
        onTap: onActivate,
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 13, color: GColors.fgSecondary), const SizedBox(width: 7)],
          Flexible(child: Text(label, style: _labelStyle, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      const SizedBox(height: GSpace.s2),
      if (readOnly) box else GFocusable(borderRadius: GRadius.chip, autofocus: autofocus, onActivate: onActivate, child: box),
    ]);
  }
}

/// A small outlined badge, for a card's title bar ("Connected as @user").
class SettingsBadge extends StatelessWidget {
  const SettingsBadge(this.text, {super.key, this.color = GColors.success});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(GRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text, style: TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w600, color: color)),
      );
}

enum SettingsButtonKind { tonal, primary, danger }

/// A button in a card: tonal, purple or red, with an icon. Without a
/// label it is a square icon button ([semanticLabel] names it).
class SettingsButton extends StatelessWidget {
  const SettingsButton({
    super.key,
    this.label,
    required this.icon,
    required this.onActivate,
    this.kind = SettingsButtonKind.tonal,
    this.semanticLabel,
    this.autofocus = false,
  });

  final String? label;
  final IconData icon;

  /// Null greys the button out.
  final VoidCallback? onActivate;
  final SettingsButtonKind kind;
  final String? semanticLabel;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final enabled = onActivate != null;
    final bg = !enabled
        ? GColors.bgElevated
        : switch (kind) {
            SettingsButtonKind.tonal => GColors.surface,
            SettingsButtonKind.primary => GColors.primary,
            SettingsButtonKind.danger => GColors.dangerFill,
          };
    final fg = enabled ? GColors.fg : GColors.fgMuted;
    return GFocusable(
      borderRadius: GRadius.chip,
      autofocus: autofocus,
      onActivate: onActivate,
      semanticLabel: semanticLabel ?? label,
      child: Container(
        height: 40,
        width: label == null ? 40 : null,
        padding: label == null ? null : const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(GRadius.chip)),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: fg),
          if (label != null) ...[
            const SizedBox(width: GSpace.s2),
            Text(label!, style: TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w700, color: fg)),
          ],
        ]),
      ),
    );
  }
}

/// An on/off setting: the row takes focus, A flips it; a switch on the right.
class SettingsToggle extends StatelessWidget {
  const SettingsToggle({super.key, required this.label, this.note, required this.on, required this.onChanged});

  final String label;
  final String? note;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GFocusable(
        borderRadius: GRadius.chip,
        onActivate: () => onChanged(!on),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: const TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w700)),
                if (note != null) ...[const SizedBox(height: 2), Text(note!, style: _noteStyle)],
              ]),
            ),
            const SizedBox(width: GSpace.s4),
            AnimatedContainer(
              duration: GMotion.fast,
              width: 40,
              height: 22,
              padding: const EdgeInsets.all(3),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on ? GColors.primary : GColors.borderStrong,
                borderRadius: BorderRadius.circular(GRadius.pill),
              ),
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(color: GColors.fg, shape: BoxShape.circle),
              ),
            ),
          ]),
        ),
      );
}

/// A row that opens something: an icon, the label, a hint on the right and
/// a chevron.
class SettingsLinkRow extends StatelessWidget {
  const SettingsLinkRow(
      {super.key, required this.icon, required this.label, this.value, required this.onActivate, this.autofocus = false});

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onActivate;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => GFocusable(
        borderRadius: GRadius.chip,
        autofocus: autofocus,
        onActivate: onActivate,
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GSpace.s2),
            child: Row(children: [
              Icon(icon, size: 17, color: GColors.fgSecondary),
              const SizedBox(width: GSpace.s3),
              Expanded(child: Text(label, style: const TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w600))),
              if (value != null)
                Flexible(
                  child: Text(value!,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted)),
                ),
              const SizedBox(width: GSpace.s2),
              const Icon(Icons.chevron_right, size: 18, color: GColors.fgMuted),
            ]),
          ),
        ),
      );
}
