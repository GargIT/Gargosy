import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_library_api.dart';
import '../../library/game_versions.dart';
import '../../library/library_snapshot.dart';
import '../../library/local_gallery.dart';
import '../../providers/library_providers.dart';
import '../screens/gallery_view.dart';
import '../theme/tokens.dart';
import '../widgets/gallery_bar.dart';
import 'search_header.dart';

/// Search (#132), like a collection's page: the header with the box, then the
/// games under the filter and sort bar. Before anything is typed it's the
/// whole library by name; a term sorts by Best match. The header goes once
/// the games are scrolled, and the box moves onto the bar. A term submitted,
/// or one a game is opened from, goes into the profile's recent searches.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  String? _term;
  bool _collapsed = false;

  /// The one box, in the header or on the bar: its state (typing, the
  /// on-screen keyboard) moves with it.
  final _boxKey = GlobalKey(debugLabel: 'search-box');

  // As a collection's page: scrolled this far the header goes, and it comes
  // back at the top, only when the grid stays scrolled without it.
  static const _hideAt = 48.0;
  static const _headerHeight = 250.0;

  void _remember([String? term]) {
    final t = term ?? _term;
    if (t != null) ref.read(recentSearchesProvider.notifier).remember(t);
  }

  void _run(String term) {
    setState(() => _term = term);
    _remember(term);
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
    final scopeQuery = GalleryQuery(search: _term);
    final scope = ref.watch(galleryScopeProvider(scopeQuery)).valueOrNull;
    final onPc = foldVersions(
      localGallery(ref.watch(gamesOnThisPcProvider), scopeQuery, inScope: (_) => true, installedAt: (_) => null),
    ).length;
    final box = FilterField(
      key: _boxKey,
      hint: 'Search your library',
      text: _term ?? '',
      large: !_collapsed,
      autofocus: true,
      onChanged: (t) => setState(() => _term = t.trim().isEmpty ? null : t.trim()),
      onSubmitted: _remember,
    );
    final recent = ref.watch(recentSearchesProvider);
    return Padding(
      key: const Key('page-Search'),
      padding: const EdgeInsets.only(top: GLayout.navHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: GMotion.fast,
            curve: GMotion.easeOut,
            alignment: Alignment.topCenter,
            child: _collapsed
                ? const SizedBox(width: double.infinity)
                : SearchHeader(
                    key: const ValueKey('search-header'),
                    box: box,
                    scope: scope,
                    onThisPc: onPc,
                    recent: recent,
                    onRecent: _run,
                    onForget: (t) => ref.read(recentSearchesProvider.notifier).forget(t),
                  ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: GalleryView(
                query: const GalleryQuery(),
                search: _term,
                bestMatch: true,
                pinnedBar: true,
                autofocus: false,
                platforms: scope?.platforms,
                barLeading: _collapsed ? SizedBox(width: 320, child: box) : null,
                onOpened: (_) => _remember(),
                emptyText: _term == null ? 'No games in your library yet.' : 'Nothing matches "$_term".',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
