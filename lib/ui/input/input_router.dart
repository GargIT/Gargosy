import 'dart:async';

import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/ui_sound_service.dart';
import '../../core/input/gamepad_service.dart';
import '../../core/input/input_action_bus.dart';
import '../../providers/sound_providers.dart';
import '../../providers/ui_provider.dart';
import 'gargosy_intents.dart';

/// Turns controller actions (from [GamepadService] via [inputActionBus]), a
/// few keys and the mouse's back button (as Escape) into intents on the
/// focused widget, and tracks the input mode.
/// The D-pad itself is handled by [GamepadService], which moves focus.
/// Plays the sounds (#237): A, B, LB/RB and their keys when something takes
/// them, and a focus the D-pad or an arrow key moved.
class InputRouter extends ConsumerStatefulWidget {
  const InputRouter({super.key, required this.child, required this.navigatorKey, this.startGamepads = true});

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  /// False in tests: don't start the gamepad plugin.
  final bool startGamepads;

  @override
  ConsumerState<InputRouter> createState() => _InputRouterState();
}

class _InputRouterState extends ConsumerState<InputRouter> {
  StreamSubscription<GameAction>? _sub;
  StreamSubscription<void>? _moves;

  static const _intents = <GameAction, Intent>{
    GameAction.confirm: ActivateIntent(),
    GameAction.confirmHold: LongActivateIntent(),
    GameAction.back: BackIntent(),
    GameAction.detail: DetailIntent(),
    GameAction.favorite: FavoriteIntent(),
    GameAction.l1: PrevTabIntent(),
    GameAction.r1: NextTabIntent(),
    GameAction.start: MenuIntent(),
  };

  @override
  void initState() {
    super.initState();
    if (widget.startGamepads) ref.read(gamepadServiceProvider);
    _sub = inputActionBus.stream.listen((action) {
      final intent = _intents[action];
      if (intent != null) _invoke(intent);
    });
    HardwareKeyboard.instance.addHandler(_onKey);
    // Only a move the player made: the D-pad (GamepadService) or the arrow
    // keys, never a focus a page, a dialog or the window gives itself.
    _moves = focusMovedBus.stream.listen((_) => _sound(UiSound.move));
    FocusManager.instance.addListener(_onFocus);
  }

  void _sound(UiSound sound) => ref.read(uiSoundsProvider).play(sound);

  /// Where focus was when an arrow key went down, until that frame ends.
  FocusNode? _arrowFrom;

  void _onFocus() {
    final from = _arrowFrom;
    if (from == null || identical(FocusManager.instance.primaryFocus, from)) return;
    _arrowFrom = null;
    _sound(UiSound.move);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && ref.read(inputModeProvider) != InputMode.keyboard) {
      ref.read(inputModeProvider.notifier).state = InputMode.keyboard;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    // Typing (a space, Enter, Escape or an arrow in a text box) isn't heard.
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) return false;
    final key = event.logicalKey;
    if (_arrows.contains(key)) {
      // The key moves focus after this handler: heard if it does, before
      // the frame ends.
      _arrowFrom = FocusManager.instance.primaryFocus;
      SchedulerBinding.instance
        ..addPostFrameCallback((_) => _arrowFrom = null)
        ..scheduleFrame();
      return false;
    }
    if (event is KeyRepeatEvent) return false;
    final intent = _keyIntents[key];
    final sound = intent == null ? null : _soundOf(intent);
    if (sound != null && _taken(intent!)) _sound(sound);
    return false;
  }

  static final _arrows = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  /// The keys that do what A, B and LB/RB do, as the intents they become.
  static final _keyIntents = <LogicalKeyboardKey, Intent>{
    LogicalKeyboardKey.enter: const ActivateIntent(),
    LogicalKeyboardKey.numpadEnter: const ActivateIntent(),
    LogicalKeyboardKey.space: const ActivateIntent(),
    LogicalKeyboardKey.escape: const BackIntent(),
    LogicalKeyboardKey.pageUp: const PrevTabIntent(),
    LogicalKeyboardKey.pageDown: const NextTabIntent(),
  };

  /// Whether [intent] does something where the focus is: an enabled action
  /// takes it, or, for Back, a page can be closed.
  bool _taken(Intent intent) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null) {
      final action = Actions.maybeFind<Intent>(context, intent: intent);
      if (action != null && !identical(action, _pop) && action.isEnabled(intent)) return true;
    }
    return intent is BackIntent && (widget.navigatorKey.currentState?.canPop() ?? false);
  }

  /// Back when nothing nearer takes it: the page closes.
  late final _pop = CallbackAction<BackIntent>(onInvoke: (_) => widget.navigatorKey.currentState?.maybePop());

  static UiSound? _soundOf(Intent intent) => switch (intent) {
    ActivateIntent() => UiSound.open,
    BackIntent() => UiSound.back,
    PrevTabIntent() || NextTabIntent() => UiSound.tab,
    _ => null,
  };

  void _invoke(Intent intent) {
    final sound = _soundOf(intent);
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null) {
      final action = Actions.maybeFind<Intent>(context, intent: intent);
      if (action != null && action.isEnabled(intent)) {
        if (sound != null && _taken(intent)) _sound(sound);
        Actions.invoke(context, intent);
        return;
      }
    }
    if (intent is BackIntent) {
      if (_taken(intent)) _sound(UiSound.back);
      widget.navigatorKey.currentState?.maybePop();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _moves?.cancel();
    FocusManager.instance.removeListener(_onFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        if (ref.read(inputModeProvider) != InputMode.mouse) {
          ref.read(inputModeProvider.notifier).state = InputMode.mouse;
        }
        if (e.buttons & kBackMouseButton != 0) _invoke(const BackIntent());
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): BackIntent(),
          SingleActivator(LogicalKeyboardKey.pageUp): PrevTabIntent(),
          SingleActivator(LogicalKeyboardKey.pageDown): NextTabIntent(),
          SingleActivator(LogicalKeyboardKey.f11): ToggleFullscreenIntent(),
        },
        child: Actions(actions: {BackIntent: _pop}, child: widget.child),
      ),
    );
  }
}
