import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/gamepad_service.dart';
import '../../../library/home_layout.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/ui_provider.dart';
import '../../theme/tokens.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/hint_bar.dart';

/// Customize Home (#139), from the end of Home: [HomeLayoutEditor] in a
/// dialog; B closes it, every change is kept as it's made.
Future<void> showCustomizeHome(BuildContext context) => showDialog<void>(
  context: context,
  builder: (c) => Center(
    child: Material(
      color: GColors.panel,
      borderRadius: BorderRadius.circular(GRadius.lg),
      child: SizedBox(
        width: 900,
        child: Padding(
          padding: const EdgeInsets.all(GSpace.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Customize Home',
                style: TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: GSpace.s1),
              const Text("This profile's Home only. Changes show at once.", style: TextStyle(color: GColors.fgMuted)),
              const SizedBox(height: GSpace.s5),
              const Flexible(child: SingleChildScrollView(child: HomeLayoutEditor(autofocus: true))),
              const SizedBox(height: GSpace.s4),
              const HintBar(hints: [Hint(GameAction.confirm, 'On / off'), Hint(GameAction.back, 'Done')]),
            ],
          ),
        ),
      ),
    ),
  ),
);

/// What's at the top of Home, its widgets on or off, and its rows on or off
/// and in order (↑ ↓ beside each), for the active profile; Reset to the
/// default. Also Settings → Home.
class HomeLayoutEditor extends ConsumerWidget {
  const HomeLayoutEditor({super.key, this.autofocus = false});

  final bool autofocus;

  static Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: GSpace.s2),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: GFont.xs,
        letterSpacing: 1,
        fontWeight: FontWeight.w700,
        color: GColors.fgSecondary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(homeLayoutProvider);
    final home = ref.read(homeLayoutProvider.notifier);
    final mouse = ref.watch(inputModeProvider) == InputMode.mouse;

    Widget check(Key key, String label, String note, bool on, VoidCallback onToggle, {bool autofocus = false}) =>
        GFocusable(
          key: key,
          autofocus: autofocus,
          borderRadius: GRadius.md,
          onActivate: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GSpace.s3, vertical: GSpace.s2),
            child: Row(
              children: [
                Icon(
                  on ? Icons.check_box : Icons.check_box_outline_blank,
                  color: on ? GColors.primary : GColors.fgMuted,
                ),
                const SizedBox(width: GSpace.s3),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: GFont.lg, color: on ? GColors.fg : GColors.fgSecondary),
                  ),
                ),
                if (note.isNotEmpty)
                  Flexible(
                    child: Text(
                      note,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                    ),
                  ),
              ],
            ),
          ),
        );

    Widget arrow(Key key, IconData icon, String label, VoidCallback? onPress) => GFocusable(
      key: key,
      borderRadius: GRadius.pill,
      onActivate: onPress,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.all(GSpace.s2),
        child: Icon(icon, size: 20, color: onPress == null ? GColors.fgFaint : GColors.fgSecondary),
      ),
    );

    final top = Wrap(
      spacing: GSpace.s2,
      children: [
        for (final t in HomeTop.values)
          GFocusable(
            key: ValueKey('home-top-${t.name}'),
            borderRadius: GRadius.pill,
            onActivate: () => home.change((l) => l.copyWith(top: t)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
              decoration: BoxDecoration(
                color: layout.top == t ? GColors.fg : GColors.surface,
                borderRadius: BorderRadius.circular(GRadius.pill),
              ),
              child: Text(
                t.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: layout.top == t ? GColors.bg : GColors.fgSecondary,
                ),
              ),
            ),
          ),
      ],
    );

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('AT THE TOP'),
        top,
        const SizedBox(height: GSpace.s5),
        _heading('WIDGETS'),
        for (var i = 0; i < HomeWidget.values.length; i++)
          check(
            ValueKey('home-widget-${HomeWidget.values[i].name}'),
            HomeWidget.values[i].label,
            HomeWidget.values[i].note,
            layout.widgets.contains(HomeWidget.values[i]),
            () => home.change((l) => l.withWidget(HomeWidget.values[i], !l.widgets.contains(HomeWidget.values[i]))),
          ),
        const SizedBox(height: GSpace.s5),
        GFocusable(
          key: const ValueKey('home-reset'),
          borderRadius: GRadius.pill,
          onActivate: home.reset,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GRadius.pill),
              border: Border.all(color: GColors.borderStrong),
            ),
            child: const Text('Reset to the default', style: TextStyle(color: GColors.fgSecondary)),
          ),
        ),
      ],
    );

    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('ROWS, IN ORDER'),
        for (var i = 0; i < layout.rows.length; i++)
          Row(
            // The same row's widgets (and their focus) follow it as it moves.
            key: ValueKey('home-row-${layout.rows[i].$1.name}'),
            children: [
              Expanded(
                child: check(
                  ValueKey('home-row-check-${layout.rows[i].$1.name}'),
                  layout.rows[i].$1.label,
                  mouse ? '' : layout.rows[i].$1.note,
                  layout.rows[i].$2,
                  () => home.change(
                    (l) => l.withRow(layout.rows[i].$1, !l.rows.firstWhere((e) => e.$1 == layout.rows[i].$1).$2),
                  ),
                  autofocus: autofocus && i == 0,
                ),
              ),
              arrow(
                ValueKey('home-row-up-${layout.rows[i].$1.name}'),
                Icons.arrow_upward,
                'Up',
                i == 0 ? null : () => home.change((l) => l.moved(layout.rows[i].$1, -1)),
              ),
              arrow(
                ValueKey('home-row-down-${layout.rows[i].$1.name}'),
                Icons.arrow_downward,
                'Down',
                i == layout.rows.length - 1 ? null : () => home.change((l) => l.moved(layout.rows[i].$1, 1)),
              ),
            ],
          ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: GSpace.s8),
        Expanded(child: rows),
      ],
    );
  }
}
