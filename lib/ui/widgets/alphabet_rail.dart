import 'package:flutter/material.dart';

import '../../library/letter_index.dart';
import '../theme/tokens.dart';
import 'g_focusable.dart';

/// The A–Z rail on a games page's right (RomM v2's): `#` and A to Z, the
/// ones with games bright. A click, A or D-pad left on a letter jumps to its
/// first game ([onJump]); up and down move between the letters there are.
/// The letter of the games at the top of the grid ([current]) is lit, so it
/// follows the scrolling.
class AlphabetRail extends StatefulWidget {
  const AlphabetRail({super.key, required this.letters, required this.onJump, this.current});

  static const width = 28.0;

  /// The letters with games.
  final Set<String> letters;
  final ValueChanged<String> onJump;

  /// The letter the games at the top of the grid are under.
  final String? current;

  @override
  State<AlphabetRail> createState() => AlphabetRailState();
}

class AlphabetRailState extends State<AlphabetRail> {
  final _nodes = {for (final l in railLetters) l: FocusNode(debugLabel: 'rail $l')};

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Puts focus on [letter] (X on a games page), or on the nearest letter
  /// after it with games.
  void focusLetter(String letter) {
    final from = railLetters.indexOf(letter).clamp(0, railLetters.length - 1);
    final target = [
      ...railLetters.skip(from),
      ...railLetters.take(from).toList().reversed,
    ].where(widget.letters.contains).firstOrNull;
    if (target != null) _nodes[target]!.requestFocus();
  }

  String? _letterOf(FocusNode node) => _nodes.entries.where((e) => e.value == node).firstOrNull?.key;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: _RailPolicy(
        onLeft: (node) {
          final l = _letterOf(node);
          if (l == null) return false;
          widget.onJump(l);
          return true;
        },
      ),
      child: SizedBox(
        width: AlphabetRail.width,
        child: Column(
          key: const ValueKey('alphabet-rail'),
          children: [
            for (final l in railLetters)
              Expanded(
                child: widget.letters.contains(l)
                    ? GFocusable(
                        key: ValueKey('rail-$l'),
                        focusNode: _nodes[l],
                        borderRadius: GRadius.sm,
                        onActivate: () => widget.onJump(l),
                        semanticLabel: 'Jump to $l',
                        child: _Letter(l, on: true, current: l == widget.current),
                      )
                    : _Letter(l, on: false),
              ),
          ],
        ),
      ),
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter(this.letter, {required this.on, this.current = false});
  final String letter;
  final bool on;
  final bool current;

  @override
  Widget build(BuildContext context) => Center(
    child: AnimatedContainer(
      key: current ? const ValueKey('rail-current') : null,
      duration: GMotion.fast,
      width: AlphabetRail.width - 4,
      decoration: BoxDecoration(
        color: current ? GColors.primary.withValues(alpha: 0.28) : null,
        borderRadius: BorderRadius.circular(GRadius.sm),
      ),
      child: FittedBox(
        child: Text(
          letter,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: GFont.sm,
            fontWeight: FontWeight.w700,
            color: current
                ? GColors.fg
                : on
                ? GColors.fgSecondary
                : GColors.fgFaint,
          ),
        ),
      ),
    ),
  );
}

/// D-pad left on a letter jumps into the grid at it, instead of moving to
/// whichever cover is nearest; the other directions move as usual.
class _RailPolicy extends ReadingOrderTraversalPolicy {
  _RailPolicy({required this.onLeft});

  final bool Function(FocusNode node) onLeft;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (direction == TraversalDirection.left && onLeft(currentNode)) return true;
    return super.inDirection(currentNode, direction);
  }
}
