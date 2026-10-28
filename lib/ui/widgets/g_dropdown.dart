import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'g_focusable.dart';
import '../../l10n/tr.dart';

/// A field that opens a list under itself, as RomM's settings selects: an
/// outlined box with an icon, the value and a chevron.
class GDropdownField extends StatelessWidget {
  const GDropdownField({
    super.key,
    required this.icon,
    required this.text,
    required this.onPress,
    this.open = false,
    this.compact = false,
  });

  final IconData icon;
  final String text;

  /// Null greys the field out.
  final VoidCallback? onPress;
  final bool open;

  /// As wide as its text (a row of settings), not the panel.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPress != null;
    final fg = enabled ? GColors.fg : GColors.fgFaint;
    return GFocusable(
      borderRadius: GRadius.lg,
      onActivate: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s3, vertical: GSpace.s3),
        decoration: BoxDecoration(
          color: GColors.bg.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(GRadius.lg),
          border: Border.all(color: open ? GColors.primary : GColors.borderStrong, width: 1.5),
        ),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(icon, size: 18, color: enabled ? GColors.fgSecondary : GColors.fgFaint),
            const SizedBox(width: GSpace.s2),
            Flexible(
              fit: compact ? FlexFit.loose : FlexFit.tight,
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600, color: fg),
              ),
            ),
            const SizedBox(width: GSpace.s2),
            Icon(
              open ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: enabled ? GColors.fgSecondary : GColors.fgFaint,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the list for the field built under [field]: right below it, as
/// wide (at least 220), above it when there's no room below. A picks, B or a
/// click outside closes it. [headings] go above the item at their index, and
/// are never focused. The index picked, or null.
Future<int?> showDropdown(
  BuildContext context, {
  required GlobalKey field,
  required List<String> labels,
  int? current,
  Map<int, String> headings = const {},
}) {
  final box = field.currentContext?.findRenderObject() as RenderBox?;
  final overlay = Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null || !box.attached) return Future.value();
  final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  return Navigator.of(context).push(_DropdownRoute(rect: rect, labels: labels, current: current, headings: headings));
}

class _DropdownRoute extends PopupRoute<int> {
  _DropdownRoute({required this.rect, required this.labels, required this.current, required this.headings});

  final Rect rect;
  final List<String> labels;
  final int? current;
  final Map<int, String> headings;

  static const _gap = 6.0;
  static const _rowHeight = 46.0;
  static const _headingHeight = 30.0;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => tr('Close');

  @override
  Duration get transitionDuration => GMotion.fast;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> _, Widget child) =>
      FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> _) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = math.max(rect.width, 220.0);
        final left = math.min(rect.left, c.maxWidth - width - GSpace.s4).clamp(0.0, double.infinity);
        final wanted = labels.length * _rowHeight + headings.length * _headingHeight + GSpace.s2 * 2;
        final below = c.maxHeight - rect.bottom - _gap - GSpace.s4;
        final above = rect.top - _gap - GSpace.s4;
        final down = below >= math.min(wanted, 200) || below >= above;
        final list = Material(
          type: MaterialType.transparency,
          child: Container(
            key: const ValueKey('dropdown-list'),
            constraints: BoxConstraints(maxHeight: down ? below : above),
            padding: const EdgeInsets.all(GSpace.s2),
            decoration: BoxDecoration(
              color: GColors.panel,
              borderRadius: BorderRadius.circular(GRadius.lg),
              border: Border.all(color: GColors.borderStrong),
              boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8))],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < labels.length; i++) ...[
                    if (headings[i] != null) _heading(headings[i]!),
                    _item(context, i),
                  ],
                ],
              ),
            ),
          ),
        );
        return Stack(
          children: [
            Positioned(
              left: left,
              width: width,
              top: down ? rect.bottom + _gap : null,
              bottom: down ? null : c.maxHeight - rect.top + _gap,
              child: list,
            ),
          ],
        );
      },
    );
  }

  Widget _heading(String text) => Container(
    height: _headingHeight,
    alignment: Alignment.bottomLeft,
    padding: const EdgeInsets.fromLTRB(GSpace.s3, 0, GSpace.s3, GSpace.s1),
    child: Text(
      text,
      style: const TextStyle(fontSize: GFont.xs, fontWeight: FontWeight.w700, letterSpacing: 1, color: GColors.fgMuted),
    ),
  );

  Widget _item(BuildContext context, int i) {
    final chosen = i == current;
    return GFocusable(
      key: chosen ? const ValueKey('dropdown-current') : null,
      autofocus: i == (current ?? 0),
      borderRadius: GRadius.md,
      onActivate: () => Navigator.of(context).pop(i),
      child: Container(
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s3),
        decoration: BoxDecoration(
          color: chosen ? GColors.surface : null,
          borderRadius: BorderRadius.circular(GRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                labels[i],
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600, color: chosen ? GColors.primary : GColors.fg),
              ),
            ),
            if (chosen) const Icon(Icons.check, size: 18, color: GColors.primary),
          ],
        ),
      ),
    );
  }
}
