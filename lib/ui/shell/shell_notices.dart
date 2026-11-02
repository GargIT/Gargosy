import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/library_snapshot.dart';
import '../../play/play_controller.dart';
import '../../providers/notification_providers.dart';
import '../../providers/romm_providers.dart';
import '../screens/game/game_screen.dart';
import '../widgets/toast.dart';

/// Says the shell's notices (#241), one at a time, never while a game runs
/// (they wait and come after), and looks for other players' new shares of
/// the games on this PC that the profile may see: the newest
/// [ShellNotices.perLook] when the profile opens, then the next ones every
/// [ShellNotices.every], round all of them.
class ShellNotices extends ConsumerStatefulWidget {
  const ShellNotices({super.key, required this.child});

  final Widget child;

  /// How long one notice shows before the next.
  static const spacing = Duration(seconds: 4);

  /// The games on this PC looked at each time.
  static const perLook = 20;

  /// How often the next games are looked at.
  static const every = Duration(minutes: 5);

  @override
  ConsumerState<ShellNotices> createState() => _ShellNoticesState();
}

class _ShellNoticesState extends ConsumerState<ShellNotices> {
  bool _showing = false;
  Timer? _next;
  Timer? _looks;
  int _cursor = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _look();
      _drain();
    });
    // No timer where RomM's heartbeat is off (tests).
    if (ref.read(rommHeartbeatEnabledProvider)) _looks = Timer.periodic(ShellNotices.every, (_) => _look());
  }

  @override
  void dispose() {
    _next?.cancel();
    _looks?.cancel();
    super.dispose();
  }

  void _look() {
    if (!mounted || !ref.read(notificationsOnProvider) || ref.read(rommOfflineProvider)) return;
    final watch = ref.read(shareWatchProvider);
    if (watch == null) return;
    final games = {for (final g in ref.read(shownGamesOnThisPcProvider)) g.id: g.displayName};
    final (ids, cursor) = nextRound(games.keys.toList(), _cursor, ShellNotices.perLook);
    _cursor = cursor;
    unawaited(watch.check({for (final id in ids) id: games[id]!}));
  }

  void _drain() {
    if (!mounted || _showing) return;
    if (ref.read(playControllerProvider).runningGameId != null) return;
    final notice = ref.read(noticesProvider.notifier).take();
    if (notice == null) return;
    // A download's news isn't said on that game's own page: its button says it.
    if (notice.downloads == 1 && notice.gameId != null && gamePageInFront(notice.gameId!)) {
      scheduleMicrotask(_drain);
      return;
    }
    // After a toast the player's own action showed, not over it.
    showToast(context, notice.text, queued: true);
    _showing = true;
    _next = Timer(ShellNotices.spacing, () {
      _showing = false;
      _drain();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(noticesProvider, (_, _) => scheduleMicrotask(_drain));
    ref.listen(playControllerProvider.select((s) => s.runningGameId), (_, now) {
      if (now == null) scheduleMicrotask(_drain);
    });
    return widget.child;
  }
}
