import 'package:flutter/material.dart';

import '../../../core/romm/game_overview.dart';
import '../../../core/romm/romm_models.dart';
import '../../theme/tokens.dart';

/// The Overview's fact rows (#179), label on the left as on RomM's page:
/// how many play, and the age ratings. Nothing when RomM has neither.
class OverviewFacts extends StatelessWidget {
  const OverviewFacts({super.key, required this.game});

  final Game game;

  /// The icon for a provider's free-text player count ("1", "1-4", "Up to
  /// 4 players", "Massively Multiplayer"): by the largest number in it.
  static IconData playersIcon(String count) {
    final numbers = RegExp(r'\d+').allMatches(count).map((m) => int.parse(m[0]!));
    final most = numbers.isEmpty ? null : numbers.reduce((a, b) => a > b ? a : b);
    return switch (most) {
      1 => Icons.person_outline,
      2 => Icons.people_outline,
      _ => Icons.groups_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final players = game.playerCount?.trim();
    final ratings = game.overview.ageRatings;
    final rows = [
      if (players != null && players.isNotEmpty) ('Players', [_Badge(players, icon: playersIcon(players))]),
      if (ratings.isNotEmpty) ('Age rating', [for (final r in ratings) _Badge(r)]),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: GSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, badges) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: GSpace.s2),
              child: Row(
                children: [
                  SizedBox(width: 120, child: _Label(label)),
                  Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: badges)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// HowLongToBeat's times as RomM's strip shows them (#179): one column a
/// play style.
class HltbStrip extends StatelessWidget {
  const HltbStrip(this.hltb, {super.key});

  final HowLongToBeat hltb;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Label('How long to beat'),
      const SizedBox(height: GSpace.s2),
      Container(
        padding: const EdgeInsets.symmetric(vertical: GSpace.s3),
        decoration: BoxDecoration(
          color: GColors.bgElevated,
          border: Border.all(color: GColors.border),
          borderRadius: BorderRadius.circular(GRadius.lg),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (final (i, (label, seconds)) in hltb.entries.indexed) ...[
                if (i > 0) const VerticalDivider(width: 1, thickness: 1, color: GColors.border),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        hltbTime(seconds),
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 3),
                      _Label(label),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: GColors.fgMuted),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: GSpace.s1),
    decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.chip)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 15, color: GColors.fgSecondary), const SizedBox(width: 6)],
        Text(
          text,
          style: const TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}
