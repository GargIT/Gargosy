import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/g_focusable.dart';

/// A section's heading and its note.
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.title, {super.key, this.note});
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: GSpace.s5, bottom: GSpace.s3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700)),
          if (note != null) ...[
            const SizedBox(height: GSpace.s1),
            Text(note!, style: const TextStyle(color: GColors.fgMuted)),
          ],
        ]),
      );
}

/// One setting: its label, what it is now, and A to change it.
class SettingsRow extends StatelessWidget {
  const SettingsRow(
      {super.key, required this.label, this.value, this.onActivate, this.danger = false, this.trailing, this.autofocus = false});

  final String label;
  final String? value;
  final VoidCallback? onActivate;
  final bool danger;
  final Widget? trailing;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: GSpace.s2),
        child: GFocusable(
          borderRadius: GRadius.lg,
          autofocus: autofocus,
          onActivate: onActivate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
            decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.lg)),
            child: Row(children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: GFont.lg, color: danger ? GColors.danger : GColors.fg, fontWeight: FontWeight.w600)),
              ),
              if (value != null) Text(value!, style: const TextStyle(color: GColors.fgSecondary)),
              ?trailing,
            ]),
          ),
        ),
      );
}

/// An on/off setting.
class SettingsToggle extends StatelessWidget {
  const SettingsToggle({super.key, required this.label, required this.on, required this.onChanged});

  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingsRow(
        label: label,
        onActivate: () => onChanged(!on),
        trailing: Padding(
          padding: const EdgeInsets.only(left: GSpace.s3),
          child: Icon(on ? Icons.toggle_on : Icons.toggle_off, size: 36, color: on ? GColors.primary : GColors.fgMuted),
        ),
      );
}
