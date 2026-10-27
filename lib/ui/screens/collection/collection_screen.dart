import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/gamepad_service.dart';
import '../../../core/romm/romm_library_api.dart';
import '../../../providers/library_providers.dart';
import '../../input/gargosy_intents.dart';
import '../../shell/backdrop.dart';
import '../../shell/page_top_bar.dart';
import '../../shell/shell_menu.dart';
import '../../theme/tokens.dart';
import '../../widgets/collection_tile.dart';
import '../../widgets/cover_grid.dart';
import '../../widgets/hint_bar.dart';
import '../gallery_view.dart';
import 'collection_header.dart';
import '../../../l10n/tr.dart';

/// A collection's page (#121), like a platform's: the header, then its games
/// under the filter and sort bar. The header goes once the games are
/// scrolled, and the name stays above the bar with a small mosaic.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, required this.collection});

  final RommCollection collection;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  bool _collapsed = false;

  /// As RomM has it now: renamed or shared from the header's ⋯ (#144).
  late RommCollection _collection = widget.collection;

  // Scrolled this far the header goes; it comes back at the top. Only when
  // the grid is long enough to stay scrolled without it.
  static const _hideAt = 48.0;
  static const _headerHeight = 240.0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    super.dispose();
  }

  // Focus left the games (up to the bar): the header comes back, so the
  // D-pad reaches Random. A cover scrolled out of the grid leaves the focus
  // on the page's scope: not that.
  void _onFocus() {
    final node = FocusManager.instance.primaryFocus;
    if (!_collapsed || node == null || !mounted || node is FocusScopeNode) return;
    if (node.context?.findAncestorWidgetOfExactType<CoverGrid>() == null) setState(() => _collapsed = false);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final px = n.metrics.pixels;
    final collapse = _collapsed ? px > 0.5 : px > _hideAt && n.metrics.maxScrollExtent > _headerHeight + _hideAt;
    if (collapse != _collapsed) setState(() => _collapsed = collapse);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = _collection;
    final name = c.isFavorite ? tr('Favourites') : c.name;
    final platforms = ref.watch(galleryScopeProvider(c.query)).valueOrNull?.platforms;
    return Actions(
      actions: {MenuIntent: CallbackAction<MenuIntent>(onInvoke: (_) => openUserMenu(context, ref))},
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Backdrop(
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: GLayout.navHeight),
                  AnimatedSize(
                    duration: GMotion.fast,
                    curve: GMotion.easeOut,
                    alignment: Alignment.topCenter,
                    child: _collapsed
                        ? Padding(
                            key: const ValueKey('collection-pinned'),
                            padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s3, GSpace.rowPad, 0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 26,
                                  child: AspectRatio(
                                    aspectRatio: CollectionTile.coverAspect,
                                    child: CollectionMosaic(
                                      urls: [for (final path in c.coverPaths.take(4)) assetUrl(ref, path)],
                                      favourite: c.isFavorite,
                                      radius: GRadius.sm,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: GSpace.s3),
                                Flexible(
                                  child: Text(
                                    name,
                                    key: const ValueKey('collection-pinned-name'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : CollectionHeader(
                            key: const ValueKey('collection-header'),
                            collection: c,
                            onChanged: (changed) => setState(() => _collection = changed),
                          ),
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: GalleryView(
                        query: c.query,
                        filterHint: tr('Filter this collection…'),
                        pinnedBar: true,
                        platforms: platforms,
                      ),
                    ),
                  ),
                  HintBar(
                    hints: [
                      Hint(GameAction.confirm, tr('Open')),
                      Hint(GameAction.favorite, tr('Favourite')),
                      Hint(GameAction.detail, tr('A–Z')),
                      Hint(GameAction.back, tr('Back')),
                    ],
                  ),
                ],
              ),
              Positioned(top: 0, left: 0, right: 0, child: PageTopBar(scrolled: _collapsed)),
            ],
          ),
        ),
      ),
    );
  }
}
