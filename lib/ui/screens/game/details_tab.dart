import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/emulator/platform_slugs.dart';
import '../../../core/romm/romm_models.dart';
import '../../../library/dsi_title.dart';
import '../../../providers/download_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/format.dart';
import '../../../l10n/tr.dart';

class DetailsTab extends ConsumerWidget {
  const DetailsTab({super.key, required this.game});

  final Game game;

  /// A DS or DSi game on this PC: what its header says about the DSi.
  DsiTitle? _dsi(WidgetRef ref) {
    if (canonicalPlatformSlug(game.platformSlug?.toLowerCase() ?? '') != 'nds') return null;
    if (!watchDownloaded(ref, game)) return null;
    return ref.watch(dsiTitleProvider(ref.read(romFilesProvider).pathFor(game))).valueOrNull;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dsi = _dsi(ref);
    final released = game.firstReleaseDate == null ? null : DateTime.fromMillisecondsSinceEpoch(game.firstReleaseDate!);
    final rows = <(String, String)>[
      (tr('Platform'), game.platformDisplayName ?? ''),
      if (released != null)
        (
          tr('Released'),
          '${released.year}-${released.month.toString().padLeft(2, '0')}-${released.day.toString().padLeft(2, '0')}',
        ),
      if (game.genres.isNotEmpty) (tr('Genres'), game.genres.join(', ')),
      if (game.companies.isNotEmpty) (tr('Companies'), game.companies.join(', ')),
      if (game.regions.isNotEmpty) (tr('Regions'), game.regions.join(', ')),
      if (game.languages.isNotEmpty) (tr('Languages'), game.languages.join(', ')),
      if (game.playerCount != null) (tr('Players'), game.playerCount!),
      if (game.averageRating != null) (tr('Rating'), decimal(game.averageRating!, 1)),
      (tr('File'), game.fsName ?? game.fileName ?? ''),
      if (game.fileSize > 0) (tr('Size'), formatBytes(game.fileSize)),
      if (game.titleId != null) (tr('Game id'), game.titleId!),
      // DSiWare runs only on a NAND of its region (#114).
      if (dsi != null && dsi.dsiWare)
        ('DSiWare', tr('Needs a DSi NAND from {0} in the bios folder', [dsiRegionLine(dsi.regions)])),
      (tr('RomM id'), game.id),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: GSpace.s14),
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: GSpace.s2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 160,
                  child: Text(
                    label,
                    style: const TextStyle(color: GColors.fgMuted, fontSize: GFont.lg),
                  ),
                ),
                Expanded(
                  child: SelectableText(value, style: const TextStyle(fontSize: GFont.lg)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
