import '../shell/shell_menu.dart';
import '../shell/page_top_bar.dart';
import '../input/gargosy_intents.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../../core/input/gamepad_service.dart';
import '../../core/romm/romm_library_api.dart';
import '../shell/backdrop.dart';
import '../theme/tokens.dart';
import '../widgets/hint_bar.dart';
import 'gallery_view.dart';

/// The filter field's hint for a gallery of [q].
String filterHintFor(GalleryQuery q) => q.platformId != null
    ? 'Filter this platform…'
    : q.inCollection
    ? 'Filter this collection…'
    : q.favourites
    ? 'Filter favourites…'
    : 'Filter…';

/// A platform's, a collection's or the favourites' games (spec §2).
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key, required this.title, required this.query, this.thisPc = false});

  final String title;
  final GalleryQuery query;

  /// Opens with On this PC on (Home's On this PC → See all).
  final bool thisPc;

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  bool _scrolled = false;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {MenuIntent: CallbackAction<MenuIntent>(onInvoke: (_) => openUserMenu(context, ref))},
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Backdrop(
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: GLayout.navHeight),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.axis != Axis.vertical) return false;
                        final s = n.metrics.pixels > 8;
                        if (s != _scrolled) setState(() => _scrolled = s);
                        return false;
                      },
                      child: GalleryView(
                        title: widget.title,
                        query: widget.query,
                        filterHint: filterHintFor(widget.query),
                        thisPc: widget.thisPc,
                      ),
                    ),
                  ),
                  const HintBar(
                    hints: [
                      Hint(GameAction.confirm, 'Open'),
                      Hint(GameAction.favorite, 'Favourite'),
                      Hint(GameAction.detail, 'A–Z'),
                      Hint(GameAction.back, 'Back'),
                    ],
                  ),
                ],
              ),
              Positioned(top: 0, left: 0, right: 0, child: PageTopBar(scrolled: _scrolled)),
            ],
          ),
        ),
      ),
    );
  }
}
