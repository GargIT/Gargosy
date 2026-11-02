import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_activity.dart';
import '../../library/library_snapshot.dart';
import '../../play/play_controller.dart';
import '../../providers/library_providers.dart';
import '../../providers/notification_providers.dart';
import '../../providers/romm_providers.dart';
import '../screens/game/game_screen.dart';
import '../widgets/toast.dart';

/// Says the shell's notices (#241), one at a time, never while a game runs
/// (they wait and come after), and looks for other players' new shares of
/// the games on this PC: when the profile opens, and when another player's
/// session of one of them ends (RomM's activity, read every 30 s).
class ShellNotices extends ConsumerStatefulWidget {
  const ShellNotices({super.key, required this.child});

  final Widget child;

  /// How long one notice shows before the next.
  static const spacing = Duration(seconds: 4);

  /// The games on this PC looked at when the profile opens, newest first.
  static const checkedAtOpen = 20;

  @override
  ConsumerState<ShellNotices> createState() => _ShellNoticesState();
}

class _ShellNoticesState extends ConsumerState<ShellNotices> {
  bool _showing = false;
  Timer? _next;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOnPc();
      _drain();
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    super.dispose();
  }

  void _checkOnPc() {
    if (!mounted || !ref.read(notificationsOnProvider) || ref.read(rommOfflineProvider)) return;
    final watch = ref.read(shareWatchProvider);
    if (watch == null) return;
    final games = ref.read(gamesOnThisPcProvider).take(ShellNotices.checkedAtOpen);
    unawaited(watch.check({for (final g in games) g.id: g.displayName}));
  }

  /// Another player's session ended on a game this PC has: did they share it?
  void _ended(List<ActivityEntry> before, List<ActivityEntry> now) {
    final watch = ref.read(shareWatchProvider);
    final me = ref.read(rommUserIdProvider);
    if (watch == null) return;
    final onPc = {for (final g in ref.read(gamesOnThisPcProvider)) g.id: g.displayName};
    final ended = {
      for (final e in before)
        if (e.userId != me &&
            onPc.containsKey(e.gameId) &&
            !now.any((n) => n.userId == e.userId && n.gameId == e.gameId))
          e.gameId: onPc[e.gameId]!,
    };
    if (ended.isNotEmpty) unawaited(watch.check(ended));
  }

  void _drain() {
    if (!mounted || _showing) return;
    if (ref.read(playControllerProvider).runningGameId != null) return;
    final notice = ref.read(noticesProvider.notifier).take();
    if (notice == null) return;
    // A download's news isn't said on that game's own page: its button says it.
    if (notice.isDownload && notice.gameId != null && gamePageInFront(notice.gameId!)) {
      scheduleMicrotask(_drain);
      return;
    }
    showToast(context, notice.text);
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
    if (ref.watch(notificationsOnProvider)) {
      ref.listen<AsyncValue<List<ActivityEntry>>>(playingNowProvider, (prev, next) {
        final before = prev?.value, now = next.value;
        if (before != null && now != null) _ended(before, now);
      });
    }
    return widget.child;
  }
}
