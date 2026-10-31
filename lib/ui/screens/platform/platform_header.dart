import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_library_api.dart';
import '../../../core/romm/romm_models.dart';
import '../../../library/library_snapshot.dart';
import '../../../providers/romm_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/download_all_button.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/format.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/platform_logo.dart';
import '../../widgets/toast.dart';
import '../game/open_game.dart';
import '../../../l10n/tr.dart';

/// The platform page's header (RomM v2's): the logo, the name with RomM's
/// type, maker and generation, four numbers, and Random.
class PlatformHeader extends ConsumerStatefulWidget {
  const PlatformHeader({super.key, required this.platform});

  final Platform platform;

  @override
  ConsumerState<PlatformHeader> createState() => _PlatformHeaderState();
}

class _PlatformHeaderState extends ConsumerState<PlatformHeader> {
  bool _picking = false;

  Future<void> _random() async {
    final api = ref.read(libraryApiProvider);
    if (api == null || _picking) return;
    setState(() => _picking = true);
    try {
      final game = await api.randomGame(platformId: widget.platform.id);
      if (!mounted) return;
      if (game == null) {
        showToast(context, tr('No games here yet.'));
      } else {
        openGame(context, game);
      }
    } on Object catch (e) {
      if (mounted) showToast(context, describeLoadError(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.platform;
    final onPc = ref.watch(shownGamesOnThisPcProvider).where((g) => g.platformId == p.id).length;
    final chips = [
      ?p.category,
      ?p.familyName,
      if (p.generation != null) tr('Generation {0}', [p.generation]),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s5, GSpace.rowPad, GSpace.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 180,
            height: 132,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.card)),
            child: PlatformLogo(slug: p.slug, size: 96),
          ),
          const SizedBox(width: GSpace.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.nameForDisplay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: GFont.xxxxl, fontWeight: FontWeight.w800, height: 1.1),
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: GSpace.s3),
                  Wrap(spacing: GSpace.s2, runSpacing: GSpace.s2, children: [for (final c in chips) _Chip(c)]),
                ],
                const SizedBox(height: GSpace.s4),
                Wrap(
                  spacing: GSpace.s10,
                  runSpacing: GSpace.s3,
                  children: [
                    _Stat('${p.gamesCount}', tr('IN LIBRARY')),
                    _Stat('$onPc', tr('ON THIS PC'), color: GColors.gargosyTeal),
                    _Stat(p.fsSizeBytes > 0 ? formatBytes(p.fsSizeBytes) : '–', tr('ON DISK')),
                    _Stat('${p.firmware.length}', tr('FIRMWARE')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: GSpace.s4),
          DownloadAllButton(query: GalleryQuery(platformId: widget.platform.id)),
          const SizedBox(width: GSpace.s2),
          GFocusable(
            key: const ValueKey('platform-random'),
            borderRadius: GRadius.pill,
            onActivate: _random,
            semanticLabel: 'Random game',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
              decoration: BoxDecoration(
                color: GColors.surface,
                borderRadius: BorderRadius.circular(GRadius.pill),
                border: Border.all(color: GColors.borderStrong),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _picking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.shuffle, size: 18),
                  const SizedBox(width: GSpace.s2),
                  Text(tr('Random'), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: GSpace.s3, vertical: GSpace.s1),
    decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
    child: Text(
      text,
      style: const TextStyle(fontSize: GFont.md, color: GColors.fgSecondary),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {this.color});
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w700, color: color),
      ),
      Text(
        label,
        style: const TextStyle(
          fontSize: GFont.sm,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: GColors.fgMuted,
        ),
      ),
    ],
  );
}
