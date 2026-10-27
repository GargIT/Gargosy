import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/romm/romm_models.dart';
import '../../../library/game_versions.dart';
import '../../../library/home_layout.dart';
import '../../../library/library_snapshot.dart';
import '../../../providers/library_providers.dart';
import '../../../core/romm/romm_library_api.dart';
import '../../screens/game/open_game.dart';
import '../../theme/tokens.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/g_focusable.dart';

/// Home's widgets (#139), those [shown]: Random pick (Y draws another) and
/// On this day side by side under the header, or stacked beside it
/// ([HomeWidgets.beside]) in a wide window; Your library as a strip under
/// them.
class HomeWidgets extends ConsumerWidget {
  const HomeWidgets({super.key, required this.shown, this.besideHeader = false});

  /// Random pick and On this day stacked, as tall as the header's cover;
  /// null when neither is shown.
  static Widget? beside(Set<HomeWidget> shown) {
    final cards = _cards(shown);
    if (cards.isEmpty) return null;
    return Column(
      key: const ValueKey('home-widgets-beside'),
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: GSpace.s4),
          SizedBox(height: stackedHeight, child: cards[i]),
        ],
      ],
    );
  }

  /// The window width from which [beside] goes next to the header.
  static const besideFrom = 1600.0;
  static const besideWidth = 440.0;

  final Set<HomeWidget> shown;

  /// Random pick and On this day are beside the header: only Your library here.
  final bool besideHeader;

  static const height = 128.0;

  /// Each of two stacked cards: the two and the gap as tall as the header's cover.
  static const stackedHeight = 120.0;

  static List<Widget> _cards(Set<HomeWidget> shown) => [
    if (shown.contains(HomeWidget.randomPick)) const _RandomPick(),
    if (shown.contains(HomeWidget.onThisDay)) const _OnThisDay(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = besideHeader ? const <Widget>[] : _cards(shown);
    final library = shown.contains(HomeWidget.library);
    if (cards.isEmpty && !library) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s2, GSpace.rowPad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cards.isNotEmpty)
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: GSpace.s4),
                    Expanded(child: cards[i]),
                  ],
                ],
              ),
            ),
          if (cards.isNotEmpty && library) const SizedBox(height: GSpace.s4),
          if (library) const _Library(),
        ],
      ),
    );
  }
}

/// A widget's frame: its label, then [child]; focusable when [onOpen] is set.
class _Card extends StatelessWidget {
  const _Card({super.key, required this.label, required this.child, this.onOpen, this.leading});

  final String label;
  final Widget child;
  final Widget? leading;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: const EdgeInsets.all(GSpace.s4),
      decoration: BoxDecoration(
        color: GColors.card,
        borderRadius: BorderRadius.circular(GRadius.card),
        border: Border.all(color: GColors.border),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: GSpace.s4)],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: GFont.xs,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: GColors.fgSecondary,
                  ),
                ),
                const SizedBox(height: GSpace.s1),
                child,
              ],
            ),
          ),
        ],
      ),
    );
    return onOpen == null ? box : GFocusable(onActivate: onOpen, child: box);
  }
}

Widget _title(String text) => Text(
  text,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700),
);

Widget _line(String text) => Text(
  text,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary),
);

String _platformYear(Game g) => [
  g.platformDisplayName,
  if (g.firstReleaseDate != null) '${DateTime.fromMillisecondsSinceEpoch(g.firstReleaseDate!, isUtc: true).year}',
].whereType<String>().join(' · ');

class _RandomPick extends ConsumerWidget {
  const _RandomPick();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(randomGameProvider).valueOrNull;
    if (game == null) return const _Card(label: 'RANDOM PICK', child: SizedBox.shrink());
    return _Card(
      key: const ValueKey('widget-random'),
      label: 'RANDOM PICK',
      onOpen: () => openGame(context, game),
      leading: CoverImage(url: coverUrlFor(ref, game, small: true), title: game.displayName, width: 66, height: 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_title(game.displayName), _line(_platformYear(game)), _line('Y: another')],
      ),
    );
  }
}

class _OnThisDay extends ConsumerWidget {
  const _OnThisDay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(onThisDayProvider).valueOrNull;
    final label = 'ON THIS DAY · ${DateFormat('d MMMM').format(DateTime.now()).toUpperCase()}';
    final game = page?.games.firstOrNull;
    if (game == null) {
      return _Card(
        key: const ValueKey('widget-on-this-day'),
        label: label,
        child: _line(page == null ? '' : 'Nothing in your library came out on this day.'),
      );
    }
    final years = DateTime.now().year - DateTime.fromMillisecondsSinceEpoch(game.firstReleaseDate!, isUtc: true).year;
    final more = page!.total - 1;
    return _Card(
      key: const ValueKey('widget-on-this-day'),
      label: label,
      onOpen: () => openGame(context, game),
      leading: CoverImage(url: coverUrlFor(ref, game, small: true), title: game.displayName, width: 66, height: 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(game.displayName),
          _line('${game.platformDisplayName ?? ''} · ${years == 1 ? '1 year' : '$years years'} ago'),
          if (more > 0) _line('and $more more from your library'),
        ],
      ),
    );
  }
}

/// Your library as one slim strip: the label, then each number with its name.
class _Library extends ConsumerWidget {
  const _Library();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(galleryScopeProvider(const GalleryQuery())).valueOrNull?.total;
    final onPc = foldVersions(ref.watch(gamesOnThisPcProvider)).length;
    final platforms = ref.watch(platformsProvider).valueOrNull?.length;
    final collections = ref.watch(collectionsProvider).valueOrNull?.length;
    String n(int? v) => v == null ? '–' : NumberFormat.decimalPattern().format(v);
    Widget stat(String value, String label, {Color? color}) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700, color: color),
          ),
          TextSpan(
            text: ' $label',
            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
          ),
        ],
      ),
    );
    return Container(
      key: const ValueKey('widget-library'),
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
      decoration: BoxDecoration(
        color: GColors.card,
        borderRadius: BorderRadius.circular(GRadius.card),
        border: Border.all(color: GColors.border),
      ),
      // One line; smaller in a narrow window rather than two lines.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          spacing: GSpace.s8,
          children: [
            const Text(
              'YOUR LIBRARY',
              style: TextStyle(
                fontSize: GFont.xs,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: GColors.fgSecondary,
              ),
            ),
            stat(n(games), 'games'),
            stat(n(onPc), 'on this PC', color: GColors.gargosyTeal),
            stat(n(platforms), 'platforms'),
            stat(n(collections), 'collections'),
          ],
        ),
      ),
    );
  }
}
