import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/retroachievements/retroachievements_game_models.dart';
import '../../../core/romm/romm_models.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/g_focusable.dart';

/// Which achievements show, by RetroAchievements' type.
enum AchievementType {
  all('All'),
  progression('Progression'),
  missable('Missable'),
  winCondition('Win condition');

  const AchievementType(this.label);
  final String label;

  /// RetroAchievements' name for it; null for [all].
  String? get raName => switch (this) {
    all => null,
    progression => 'progression',
    missable => 'missable',
    winCondition => 'win_condition',
  };
}

/// Earned, locked, or both.
enum AchievementStatus { all, earned, locked }

/// [list] with only the achievements of [type] and [status].
List<RetroAchievement> filterAchievements(
  List<RetroAchievement> list, {
  AchievementType type = AchievementType.all,
  AchievementStatus status = AchievementStatus.all,
}) => [
  for (final a in list)
    if ((type.raName == null || a.type == type.raName) &&
        switch (status) {
          AchievementStatus.all => true,
          AchievementStatus.earned => a.isUnlocked,
          AchievementStatus.locked => !a.isUnlocked,
        })
      a,
];

/// How many columns the list takes in [width]: one per 380 px, 1 to 4.
int achievementColumns(double width) => (width / 380).floor().clamp(1, 4);

/// RomM v2's Achievements tab: the game's RetroAchievements set with the
/// unlocks RomM synced for the user, a summary, filters by type and by
/// earned or locked, and each achievement's badge, in 1 to 4 columns.
class AchievementsTab extends ConsumerStatefulWidget {
  const AchievementsTab({super.key, required this.game});

  final Game game;

  @override
  ConsumerState<AchievementsTab> createState() => _AchievementsTabState();
}

class _AchievementsTabState extends ConsumerState<AchievementsTab> {
  var _type = AchievementType.all;
  var _status = AchievementStatus.all;

  Game get _game => widget.game;

  void _toggle(AchievementStatus status) =>
      setState(() => _status = _status == status ? AchievementStatus.all : status);

  @override
  Widget build(BuildContext context) {
    if (_game.raId == null || _game.raAchievements.isEmpty) {
      return const Center(
        child: Text(
          'RomM has no RetroAchievements for this game.',
          style: TextStyle(fontSize: GFont.lg, color: GColors.fgMuted),
        ),
      );
    }
    final progression = ref.watch(raProgressionProvider).valueOrNull?[_game.raId];
    final list = progression == null
        ? _game.raAchievements
        : RetroAchievementsGameProgress.fromRomm(
            gameId: _game.raId!,
            achievements: _game.raAchievements,
            progression: progression,
          ).achievements;
    final shown = filterAchievements(list, type: _type, status: _status);
    return LayoutBuilder(
      builder: (context, box) {
        final columns = achievementColumns(box.maxWidth);
        return ListView(
          padding: const EdgeInsets.only(bottom: GSpace.s14),
          children: [
            _Summary(list: list, synced: progression != null),
            const SizedBox(height: GSpace.s3),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final t in AchievementType.values)
                  _Filter(label: t.label, on: _type == t, onPress: () => setState(() => _type = t)),
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: GSpace.s1),
                  color: GColors.surfaceHover,
                ),
                _Filter(
                  label: '✓ Earned',
                  on: _status == AchievementStatus.earned,
                  tint: GColors.statusSuccess,
                  onPress: () => _toggle(AchievementStatus.earned),
                ),
                _Filter(
                  label: '⊘ Locked',
                  on: _status == AchievementStatus.locked,
                  tint: GColors.statusDanger,
                  onPress: () => _toggle(AchievementStatus.locked),
                ),
              ],
            ),
            const SizedBox(height: GSpace.s4),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: GSpace.s6),
                child: Text(
                  'No achievements match these filters.',
                  style: TextStyle(fontSize: GFont.lg, color: GColors.fgMuted),
                ),
              ),
            for (var i = 0; i < shown.length; i += columns)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < columns; c++) ...[
                        if (c > 0) const SizedBox(width: 6),
                        Expanded(child: i + c < shown.length ? _AchievementRow(shown[i + c]) : const SizedBox.shrink()),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Earned of all, points, and how many are progression and missable.
class _Summary extends StatelessWidget {
  const _Summary({required this.list, required this.synced});

  final List<RetroAchievement> list;
  final bool synced;

  @override
  Widget build(BuildContext context) {
    final earned = list.where((a) => a.isUnlocked);
    final points = list.fold(0, (sum, a) => sum + a.points);
    final earnedPoints = earned.fold(0, (sum, a) => sum + a.points);
    final progression = list.where((a) => a.type == 'progression').length;
    final missable = list.where((a) => a.type == 'missable').length;
    final stats = [
      (synced ? '${earned.length} / ${list.length}' : '${list.length}', 'Achievements', GColors.fg),
      (synced ? '$earnedPoints / $points' : '$points', 'Points', GColors.fg),
      if (progression > 0) ('$progression', 'Progression', GColors.fg),
      if (missable > 0) ('$missable', 'Missable', GColors.warning),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: GColors.bgElevated,
            border: Border.all(color: GColors.border),
            borderRadius: BorderRadius.circular(GRadius.lg),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                for (final (i, (value, label, color)) in stats.indexed) ...[
                  if (i > 0) const VerticalDivider(width: 1, thickness: 1, color: GColors.border),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: GSpace.s1),
                        Text(
                          label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                            color: GColors.fgFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!synced) ...[
          const SizedBox(height: GSpace.s2),
          const Text(
            'No progress synced to RomM yet.',
            style: TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
          ),
        ],
      ],
    );
  }
}

/// A filter pill: white when on, or [tint] for Earned and Locked.
class _Filter extends StatelessWidget {
  const _Filter({required this.label, required this.on, required this.onPress, this.tint});

  final String label;
  final bool on;
  final VoidCallback onPress;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final tint = this.tint;
    final (fill, edge, text) = !on
        ? (GColors.surface, GColors.border, GColors.fgSecondary)
        : tint == null
        ? (GColors.fg, GColors.fg, GColors.bg)
        : (tint.withValues(alpha: 0.3), tint.withValues(alpha: 0.5), GColors.fg);
    return GFocusable(
      borderRadius: GRadius.pill,
      onActivate: onPress,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: GMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: edge),
          borderRadius: BorderRadius.circular(GRadius.pill),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: GFont.sm, fontWeight: FontWeight.w500, color: text),
        ),
      ),
    );
  }
}

/// One achievement: its badge, title, description, points and type; dimmed
/// while locked.
class _AchievementRow extends ConsumerWidget {
  const _AchievementRow(this.a);

  final RetroAchievement a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = a.type;
    return GFocusable(
      borderRadius: GRadius.md,
      child: Opacity(
        opacity: a.isUnlocked ? 1 : 0.55,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: GColors.bgElevated,
            border: Border.all(color: GColors.border),
            borderRadius: BorderRadius.circular(GRadius.md),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(GRadius.md),
                child: SizedBox.square(
                  dimension: 52,
                  child: a.badgeName.isEmpty
                      ? const ColoredBox(color: GColors.bgElevated)
                      : ref.watch(coverImageBuilderProvider)(a.isUnlocked ? a.badgeUrl : a.lockedBadgeUrl),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      a.title,
                      style: const TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.description,
                      style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${a.points} pts',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: GColors.fgSecondary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (type != null) ...[const SizedBox(height: GSpace.s1), _TypeTag(type)],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Progression, missable or win condition, in RomM's colours.
class _TypeTag extends StatelessWidget {
  const _TypeTag(this.type);

  final String type;

  @override
  Widget build(BuildContext context) {
    final (label, base, text) = switch (type) {
      'progression' => ('Progression', GColors.providerIgdb, GColors.providerIgdb),
      'missable' => ('Missable', GColors.warning, GColors.warningFg),
      'win_condition' => ('Win condition', GColors.statusSuccess, GColors.success),
      _ => (type, GColors.fgSecondary, GColors.fgSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: base.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(GRadius.md)),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: text),
      ),
    );
  }
}
