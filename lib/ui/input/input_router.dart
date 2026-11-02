import 'dart:async';

import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/gamepad_service.dart';
import '../../core/audio/ui_sound_service.dart';
import '../../core/input/input_action_bus.dart';
import '../../providers/sound_providers.dart';
import '../../providers/ui_provider.dart';
import 'gargosy_intents.dart';

/// Turns controller actions (from [GamepadService] via [inputActionBus]), a
/// few keys and the mouse's back button (as Escape) into intents on the
/// focused widget, and tracks the input mode.
/// The D-pad itself is handled by [GamepadService], which moves focus.
/// Plays the sounds (#237): A, B, LB/RB and their keys, and a focus moved
/// with the controller or the keys (never the mouse).
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
  FocusNode? _focused;

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
    FocusManager.instance.addListener(_onFocus);
  }

  void _sound(UiSound sound) => ref.read(uiSoundsProvider).play(sound);

  void _onFocus() {
    final now = FocusManager.instance.primaryFocus;
    if (identical(now, _focused)) return;
    final was = _focused;
    _focused = now;
    if (was != null && now != null && ref.read(inputModeProvider) != InputMode.mouse) _sound(UiSound.move);
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && ref.read(inputModeProvider) != InputMode.keyboard) {
      ref.read(inputModeProvider.notifier).state = InputMode.keyboard;
    }
    if (event is KeyDownEvent) {
      final sound = _keySounds[event.logicalKey];
      if (sound != null) _sound(sound);
    }
    return false;
  }

  static final _keySounds = {
    LogicalKeyboardKey.enter: UiSound.open,
    LogicalKeyboardKey.numpadEnter: UiSound.open,
    LogicalKeyboardKey.space: UiSound.open,
    LogicalKeyboardKey.escape: UiSound.back,
    LogicalKeyboardKey.pageUp: UiSound.tab,
    LogicalKeyboardKey.pageDown: UiSound.tab,
  };

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
        if (sound != null) _sound(sound);
        Actions.invoke(context, intent);
        return;
      }
    }
    if (intent is BackIntent) {
      _sound(UiSound.back);
      widget.navigatorKey.currentState?.maybePop();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
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
        child: Actions(
          actions: {
            BackIntent: CallbackAction<BackIntent>(onInvoke: (_) => widget.navigatorKey.currentState?.maybePop()),
          },
          child: widget.child,
        ),
      ),
    );
  }
}
