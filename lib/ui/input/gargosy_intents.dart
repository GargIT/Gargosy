import 'package:flutter/widgets.dart';

/// B / Escape: go back. Unhandled, it pops the current route.
class BackIntent extends Intent {
  const BackIntent();
}

/// A held: the focused item's long press.
class LongActivateIntent extends Intent {
  const LongActivateIntent();
}

/// X: the focused item's details or options.
class DetailIntent extends Intent {
  const DetailIntent();
}

/// Y: favourite.
class FavoriteIntent extends Intent {
  const FavoriteIntent();
}

/// LB / PageUp.
class PrevTabIntent extends Intent {
  const PrevTabIntent();
}

/// RB / PageDown.
class NextTabIntent extends Intent {
  const NextTabIntent();
}

/// Start: the user menu.
class MenuIntent extends Intent {
  const MenuIntent();
}

/// F11.
class ToggleFullscreenIntent extends Intent {
  const ToggleFullscreenIntent();
}
