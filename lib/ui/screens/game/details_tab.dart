import 'package:flutter/material.dart';

import '../../../core/romm/romm_models.dart';
import '../../theme/tokens.dart';
import '../../widgets/format.dart';

class DetailsTab extends StatelessWidget {
  const DetailsTab({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final released = game.firstReleaseDate == null ? null : DateTime.fromMillisecondsSinceEpoch(game.firstReleaseDate!);
    final rows = <(String, String)>[
      ('Platform', game.platformDisplayName ?? ''),
      if (released != null) ('Released', '${released.year}-${released.month.toString().padLeft(2, '0')}-${released.day.toString().padLeft(2, '0')}'),
      if (game.genres.isNotEmpty) ('Genres', game.genres.join(', ')),
      if (game.companies.isNotEmpty) ('Companies', game.companies.join(', ')),
      if (game.regions.isNotEmpty) ('Regions', game.regions.join(', ')),
      if (game.languages.isNotEmpty) ('Languages', game.languages.join(', ')),
      if (game.playerCount != null) ('Players', game.playerCount!),
      if (game.averageRating != null) ('Rating', game.averageRating!.toStringAsFixed(1)),
      ('File', game.fsName ?? game.fileName ?? ''),
      if (game.fileSize > 0) ('Size', formatBytes(game.fileSize)),
      if (game.titleId != null) ('Game id', game.titleId!),
      ('RomM id', game.id),
    ];
    return ListView(padding: const EdgeInsets.only(bottom: GSpace.s14), children: [
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: GSpace.s2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 160, child: Text(label, style: const TextStyle(color: GColors.fgMuted, fontSize: GFont.lg))),
            Expanded(child: SelectableText(value, style: const TextStyle(fontSize: GFont.lg))),
          ]),
        ),
    ]);
  }
}
