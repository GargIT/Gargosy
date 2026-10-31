import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/gamepad_service.dart';
import '../../core/romm/romm_models.dart';
import '../../library/download_service.dart';
import '../../providers/download_providers.dart';
import '../../providers/library_providers.dart';
import '../shell/page_top_bar.dart';
import '../shell/backdrop.dart';
import '../theme/tokens.dart';
import '../widgets/cover_image.dart';
import '../widgets/format.dart';
import '../widgets/g_focusable.dart';
import '../widgets/hint_bar.dart';
import 'game/open_game.dart';
import '../../l10n/tr.dart';

/// Downloads (#143), from the user menu: the one running, with its speed
/// and time left; then the queue (Y puts one first); the ones that failed
/// (A tries again); the ones done this session. X stops or removes one.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  /// "1.2 GB of 4.3 GB · 12 MB/s · 4 min left" while downloading.
  static String progressLine(DownloadProgress p, Duration elapsed) {
    if (p.phase == DownloadPhase.extracting) return tr('Unpacking…');
    if (p.phase == DownloadPhase.checking) return tr('Checking…');
    final parts = <String>[
      p.total > 0 ? tr('{0} of {1}', [formatBytes(p.received), formatBytes(p.total)]) : formatBytes(p.received),
    ];
    final seconds = elapsed.inMilliseconds / 1000;
    if (seconds >= 1 && p.received > 0) {
      final speed = p.received / seconds;
      parts.add('${formatBytes(speed.round())}/s');
      if (p.total > p.received) {
        final left = Duration(seconds: ((p.total - p.received) / speed).round());
        parts.add(
          left.inMinutes >= 1 ? tr('{0} min left', [left.inMinutes]) : tr('{0} s left', [left.inSeconds.clamp(1, 59)]),
        );
      }
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(downloadsProvider);
    final downloads = ref.read(downloadsProvider.notifier);
    final current = downloads.current;
    final queue = downloads.queue;
    final failed = downloads.failed;
    final finished = downloads.finished;
    var first = true;
    bool autofocus() {
      final f = first;
      first = false;
      return f;
    }

    Widget row(Game game, String line, {Widget? below, VoidCallback? onA, VoidCallback? onX, VoidCallback? onY}) {
      return Padding(
        // On the row, so its focus moves with it when the queue reorders.
        key: ValueKey('download-${game.id}'),
        padding: const EdgeInsets.only(bottom: GSpace.s2),
        child: GFocusable(
          autofocus: autofocus(),
          onActivate: onA ?? () => openGame(context, game),
          onDetail: onX,
          onFavorite: onY,
          child: Container(
            padding: const EdgeInsets.all(GSpace.s3),
            decoration: BoxDecoration(
              color: GColors.card,
              borderRadius: BorderRadius.circular(GRadius.card),
              border: Border.all(color: GColors.border),
            ),
            child: Row(
              children: [
                CoverImage(url: coverUrlFor(ref, game, small: true), title: game.displayName, width: 45, height: 60),
                const SizedBox(width: GSpace.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: GSpace.s1),
                      Text(
                        [?game.platformDisplayName, line].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
                      ),
                      if (below != null) ...[const SizedBox(height: GSpace.s2), below],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: GSpace.s5, bottom: GSpace.s2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: GFont.xs,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
          color: GColors.fgSecondary,
        ),
      ),
    );

    final running = current == null ? null : states[current.id];
    final started = current == null ? null : downloads.startedAt(current.id);
    final empty = current == null && queue.isEmpty && failed.isEmpty && finished.isEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Backdrop(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTopBar(scrolled: false),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    key: const Key('page-Downloads'),
                    padding: const EdgeInsets.symmetric(horizontal: GSpace.s8, vertical: GSpace.s6),
                    children: [
                      Text(
                        tr('Downloads'),
                        style: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800),
                      ),
                      if (empty)
                        Padding(
                          padding: const EdgeInsets.only(top: GSpace.s5),
                          child: Text(
                            tr('Nothing downloading. A game\'s Download puts it here.'),
                            style: const TextStyle(fontSize: GFont.lg, color: GColors.fgMuted),
                          ),
                        ),
                      if (current != null && running != null) ...[
                        heading(tr('DOWNLOADING')),
                        row(
                          current,
                          progressLine(running, started == null ? Duration.zero : DateTime.now().difference(started)),
                          below: LinearProgressIndicator(value: running.fraction),
                          onX: running.phase == DownloadPhase.downloading ? () => downloads.cancel(current.id) : null,
                        ),
                      ],
                      if (queue.isNotEmpty) ...[
                        heading(tr('QUEUED · {0}', [queue.length])),
                        for (final g in queue)
                          row(
                            g,
                            // Outside Only download's window (#228): when it goes on; A starts it now.
                            [
                              g.fileSize > 0 ? tr('Queued · {0}', [formatBytes(g.fileSize)]) : tr('Queued'),
                              if (downloads.waitsUntil case final at?)
                                tr('waits until {0}', [
                                  '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                                ]),
                            ].join(' · '),
                            onA: downloads.waitsUntil == null ? null : () => downloads.startNow(g.id),
                            onX: () => downloads.cancel(g.id),
                            onY: () => downloads.moveToFront(g.id),
                          ),
                        // Under the queue: the D-pad meets the games first.
                        if (queue.length > 1)
                          Align(
                            alignment: Alignment.centerRight,
                            child: GFocusable(
                              key: const ValueKey('cancel-queued'),
                              borderRadius: GRadius.pill,
                              onActivate: downloads.cancelQueued,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: GSpace.s3, vertical: GSpace.s2),
                                child: Text(
                                  tr('Cancel all'),
                                  style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
                                ),
                              ),
                            ),
                          ),
                      ],
                      if (failed.isNotEmpty) ...[
                        heading(tr('FAILED')),
                        for (final g in failed)
                          row(
                            g,
                            tr('Failed: {0}', [states[g.id]?.error ?? '']),
                            onA: () => downloads.start(g),
                            onX: () => downloads.dismiss(g.id),
                          ),
                      ],
                      if (finished.isNotEmpty) ...[
                        heading(tr('DONE')),
                        for (final g in finished)
                          row(g, g.fileSize > 0 ? tr('On this PC · {0}', [formatBytes(g.fileSize)]) : tr('On this PC')),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            HintBar(
              hints: [
                Hint(
                  GameAction.confirm,
                  downloads.waitsUntil == null ? tr('Open · Retry') : tr('Download now · Retry'),
                ),
                Hint(GameAction.detail, tr('Stop · Remove')),
                Hint(GameAction.favorite, tr('First in the queue')),
                Hint(GameAction.back, tr('Back')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
