import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ui_provider.dart';
import '../input/gargosy_intents.dart';
import '../theme/tokens.dart';

/// Anything you can focus and press: a card, a badge, a key. Shows v2's focus
/// ring for the controller and keyboard, and a hover surface for the mouse.
class GFocusable extends ConsumerStatefulWidget {
  const GFocusable({
    super.key,
    required this.child,
    this.onActivate,
    this.onLongActivate,
    this.onDetail,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = GRadius.card,
    this.semanticLabel,
  });

  static const ringKey = Key('g-focus-ring');

  final Widget child;
  final VoidCallback? onActivate;
  final VoidCallback? onLongActivate;
  final VoidCallback? onDetail;
  final bool autofocus;
  final FocusNode? focusNode;
  final double borderRadius;
  final String? semanticLabel;

  @override
  ConsumerState<GFocusable> createState() => _GFocusableState();
}

class _GFocusableState extends ConsumerState<GFocusable> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(inputModeProvider);
    final ringWidth = switch (mode) {
      InputMode.gamepad => GFocusRing.pad,
      InputMode.keyboard => GFocusRing.key,
      InputMode.mouse => GFocusRing.mouse,
    };
    final showRing = _focused && mode != InputMode.mouse;
    final radius = BorderRadius.circular(widget.borderRadius);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        mouseCursor: SystemMouseCursors.click,
        onFocusChange: (f) => setState(() => _focused = f),
        onShowHoverHighlight: (h) => setState(() => _hovered = h),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onActivate?.call()),
          if (widget.onLongActivate != null)
            LongActivateIntent: CallbackAction<LongActivateIntent>(onInvoke: (_) => widget.onLongActivate!()),
          if (widget.onDetail != null) DetailIntent: CallbackAction<DetailIntent>(onInvoke: (_) => widget.onDetail!()),
        },
        child: GestureDetector(
          onTap: widget.onActivate,
          onLongPress: widget.onLongActivate,
          onSecondaryTap: widget.onDetail,
          child: AnimatedScale(
            scale: showRing ? 1.04 : 1,
            duration: GMotion.fast,
            curve: GMotion.easeOut,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: GMotion.fast,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    color: _hovered && mode == InputMode.mouse ? GColors.surfaceHover : null,
                  ),
                  child: widget.child,
                ),
                if (showRing)
                  Positioned.fill(
                    left: -GFocusRing.offset,
                    top: -GFocusRing.offset,
                    right: -GFocusRing.offset,
                    bottom: -GFocusRing.offset,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: GFocusable.ringKey,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(widget.borderRadius + GFocusRing.offset),
                          border: Border.all(color: GColors.fg, width: ringWidth),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
