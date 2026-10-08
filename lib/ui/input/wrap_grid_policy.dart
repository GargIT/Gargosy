import 'package:flutter/widgets.dart';

/// Directional focus that wraps in a grid (spec §7): right at the end of a
/// row goes to the start of the next, left at the start goes to the end of
/// the previous. Up and down stay directional.
class WrapGridTraversalPolicy extends ReadingOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (super.inDirection(currentNode, direction)) return true;
    return switch (direction) {
      TraversalDirection.right => next(currentNode),
      TraversalDirection.left => previous(currentNode),
      _ => false,
    };
  }
}
