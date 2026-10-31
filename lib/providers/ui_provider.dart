// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:flutter_riverpod/legacy.dart';

enum InputMode { mouse, gamepad, keyboard }

/// The input device used last; drives focus rings and the hint bar (spec §7).
final inputModeProvider = StateProvider<InputMode>((ref) => InputMode.mouse);

/// While true, the D-pad doesn't move focus (a screen handles it itself).
final navigationLockedProvider = StateProvider<bool>((ref) => false);
