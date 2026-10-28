import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/gamepad_service.dart';
import '../../core/input/input_action_bus.dart';
import '../../core/romm/romm_models.dart';
import '../../core/storage/app_preferences.dart';
import '../../library/library_snapshot.dart';
import '../../play/play_controller.dart';
import '../../profiles/profile_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/romm_providers.dart';
import '../input/gargosy_intents.dart';
import '../screens/game/open_game.dart';
import '../theme/tokens.dart';
import '../widgets/cover_image.dart';
import '../widgets/game_transition.dart';
import '../../l10n/tr.dart';

/// The screensaver's wait (#147), this PC's setting (Settings → Display):
/// minutes, 0 for off; 5 by default.
class ScreensaverDelay {
  static const prefKey = 'screensaver.minutes';
  static const choices = [0, 2, 5, 10, 30];
  static const fallback = 5;

  static int of(AppPreferences prefs) {
    final n = int.tryParse(prefs.getString(prefKey) ?? '');
    return n != null && choices.contains(n) ? n : fallback;
  }

  static String label(int minutes) => minutes == 0 ? tr('Off') : tr('After {0} minutes', [minutes]);
}

final screensaverMinutesProvider = Provider<int>((ref) => ScreensaverDelay.of(ref.watch(appPreferencesProvider)));

/// Around the shell (#147): after [ScreensaverDelay] with no controller,
/// key or mouse, shows [ScreensaverScreen] when the shell is in front (no
/// page or dialog over it) and no game runs. A on the game shown opens it.
class IdleScreensaver extends ConsumerStatefulWidget {
  const IdleScreensaver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IdleScreensaver> createState() => _IdleScreensaverState();
}

class _IdleScreensaverState extends ConsumerState<IdleScreensaver> {
  Timer? _timer;
  StreamSubscription<GameAction>? _actions;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _actions = inputActionBus.stream.listen((_) => _reset());
    HardwareKeyboard.instance.addHandler(_onKey);
    _reset();
  }

  bool _onKey(KeyEvent _) {
    _reset();
    return false;
  }

  void _reset() {
    _timer?.cancel();
    final minutes = ref.read(screensaverMinutesProvider);
    if (minutes == 0 || _showing || !mounted) return;
    _timer = Timer(Duration(minutes: minutes), _idle);
  }

  Future<void> _idle() async {
    if (!mounted) return;
    final inFront = ModalRoute.of(context)?.isCurrent ?? true;
    if (!inFront || ref.read(playControllerProvider).runningGameId != null) return _reset();
    _showing = true;
    final game = await Navigator.of(context).push<Game>(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: GMotion.slow,
        pageBuilder: (_, _, _) => const ScreensaverScreen(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
    _showing = false;
    if (!mounted) return;
    if (game != null) await openGame(context, game);
    _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _actions?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(screensaverMinutesProvider, (_, _) => _reset());
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reset(),
      onPointerHover: (_) => _reset(),
      onPointerMove: (_) => _reset(),
      onPointerSignal: (_) => _reset(),
      child: widget.child,
    );
  }
}

/// The library one game at a time (#147): its art behind, the cover, name,
/// platform and year, drifting; another every [every]. Any button, key or
/// click ends it, and that press does nothing else; A (Enter) opens the
/// game shown (popped with it).
class ScreensaverScreen extends ConsumerStatefulWidget {
  const ScreensaverScreen({super.key, this.every = const Duration(seconds: 8)});

  final Duration every;

  @override
  ConsumerState<ScreensaverScreen> createState() => _ScreensaverScreenState();
}

class _ScreensaverScreenState extends ConsumerState<ScreensaverScreen> {
  final _random = Random();
  Game? _game;
  int _seed = 0;
  Timer? _next;
  StreamSubscription<GameAction>? _actions;
  bool _done = false;
  Offset? _pointer;

  @override
  void initState() {
    super.initState();
    _pick();
    _next = Timer.periodic(widget.every, (_) => _pick());
    // The D-pad and the rest of the buttons: A comes as ActivateIntent.
    _actions = inputActionBus.stream.listen((a) {
      if (a != GameAction.confirm && a != GameAction.confirmHold) _close();
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    _actions?.cancel();
    super.dispose();
  }

  /// RomM's random game; offline, one of this PC's.
  Future<void> _pick() async {
    Game? game;
    final api = ref.read(libraryApiProvider);
    if (api != null && !ref.read(rommOfflineProvider)) {
      try {
        game = await api.randomGame();
      } on Object {
        game = null;
      }
    }
    if (game == null) {
      final here = ref.read(gamesOnThisPcProvider);
      if (here.isNotEmpty) game = here[_random.nextInt(here.length)];
    }
    if (mounted && game != null) {
      setState(() {
        _game = game;
        _seed = _random.nextInt(1 << 31);
      });
    }
  }

  void _close([Game? open]) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(open);
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    void close() => _close();
    return Actions(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _close(game)),
        for (final type in const [
          BackIntent,
          DetailIntent,
          FavoriteIntent,
          PrevTabIntent,
          NextTabIntent,
          MenuIntent,
          LongActivateIntent,
        ])
          type: CallbackAction<Intent>(onInvoke: (_) => close()),
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.handled;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) return KeyEventResult.ignored;
          close();
          return KeyEventResult.handled;
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => close(),
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) close();
          },
          onPointerHover: (e) {
            // A nudge of the desk isn't a wake-up; a real move is.
            final from = _pointer ??= e.position;
            if ((e.position - from).distance > 24) close();
          },
          child: ColoredBox(
            color: GColors.bg,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 1200),
              child: game == null
                  ? const SizedBox.expand(key: ValueKey('screensaver-empty'))
                  : _Slide(
                      key: ValueKey('screensaver-${game.id}-$_seed'),
                      game: game,
                      every: widget.every,
                      seed: _seed,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One game for [every], drifting from a random place on the screen to
/// another, zooming in or out, its cover on either side ([seed] picks).
class _Slide extends ConsumerWidget {
  const _Slide({super.key, required this.game, required this.every, required this.seed});

  final Game game;
  final Duration every;
  final int seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = game.firstReleaseDate == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(game.firstReleaseDate!, isUtc: true).year;
    final line = [game.platformDisplayName, if (year != null) '$year'].whereType<String>().join(' · ');
    final random = Random(seed);
    Alignment spot() => Alignment(random.nextDouble() * 1.6 - 0.8, random.nextDouble() * 1.6 - 0.8);
    final from = spot();
    final to = spot();
    final zoomIn = random.nextBool();
    final coverRight = random.nextBool();
    final cover = CoverImage(url: coverUrlFor(ref, game), title: game.displayName, width: 240, height: 324);
    return GameArtBackdrop(
      game: game,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: every,
        builder: (context, t, child) => Padding(
          padding: const EdgeInsets.all(GSpace.s8),
          child: Align(
            alignment: Alignment.lerp(from, to, Curves.easeInOut.transform(t))!,
            child: Transform.scale(scale: zoomIn ? 0.96 + 0.08 * t : 1.04 - 0.08 * t, child: child),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!coverRight) ...[cover, const SizedBox(width: GSpace.s8)],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.displayName,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: GFont.xxxxl, fontWeight: FontWeight.w800, height: 1.1),
                  ),
                  if (line.isNotEmpty) ...[
                    const SizedBox(height: GSpace.s3),
                    Text(
                      line,
                      style: const TextStyle(fontSize: GFont.xl, color: GColors.fgSecondary),
                    ),
                  ],
                  const SizedBox(height: GSpace.s6),
                  Text(
                    tr('A opens it · any other button goes back'),
                    style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                  ),
                ],
              ),
            ),
            if (coverRight) ...[const SizedBox(width: GSpace.s8), cover],
          ],
        ),
      ),
    );
  }
}
