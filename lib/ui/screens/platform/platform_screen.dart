import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/gamepad_service.dart';
import '../../../core/romm/romm_library_api.dart';
import '../../../core/romm/romm_models.dart';
import '../../input/gargosy_intents.dart';
import '../../shell/backdrop.dart';
import '../../shell/page_top_bar.dart';
import '../../shell/shell_menu.dart';
import '../../theme/tokens.dart';
import '../../widgets/cover_grid.dart';
import '../../widgets/hint_bar.dart';
import '../game/game_tabs.dart';
import '../gallery_view.dart';
import 'emulator_tab.dart';
import 'firmware_tab.dart';
import 'platform_header.dart';
import '../../../l10n/tr.dart';

/// A platform's page (RomM v2's, #95): the header, then the tabs Library,
/// Firmware / BIOS and Emulator, pinned with the Library's filter and sort
/// bar. The header goes once the games are scrolled, and the platform's name
/// moves into the tab row. LB/RB switch tabs; each tab keeps its focus.
class PlatformScreen extends ConsumerStatefulWidget {
  const PlatformScreen({super.key, required this.platform});

  final Platform platform;

  static List<String> get tabs => [tr('Library'), tr('Firmware / BIOS'), tr('Emulator')];

  @override
  ConsumerState<PlatformScreen> createState() => _PlatformScreenState();
}

class _PlatformScreenState extends ConsumerState<PlatformScreen> {
  int _tab = 0;
  bool _collapsed = false;
  // A node per tab to tell where focus is; not a scope, which the D-pad can't leave.
  final _tabNodes = [
    for (final t in PlatformScreen.tabs)
      FocusNode(debugLabel: 'platform-tab-$t', skipTraversal: true, canRequestFocus: false),
  ];

  /// The last focused node in each tab, given back on LB/RB.
  final _last = <int, FocusNode>{};

  // Scrolled this far the header goes; it comes back at the top. Only when
  // the grid is long enough to stay scrolled without it.
  static const _hideAt = 48.0;
  static const _headerHeight = 220.0;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_remember);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_remember);
    for (final s in _tabNodes) {
      s.dispose();
    }
    super.dispose();
  }

  void _remember() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || !mounted) return;
    for (var i = 0; i < _tabNodes.length; i++) {
      if (node.ancestors.contains(_tabNodes[i])) _last[i] = node;
    }
    // Focus left the games (up to the bar or the tabs): the header comes back,
    // so the D-pad reaches Random even when the grid isn't quite at the top.
    // A cover scrolled out of the grid leaves the focus on the page's scope: not that.
    if (_collapsed && node is! FocusScopeNode && node.context?.findAncestorWidgetOfExactType<CoverGrid>() == null) {
      setState(() => _collapsed = false);
    }
  }

  void _go(int i, {bool restoreFocus = true}) {
    if (i < 0 || i >= PlatformScreen.tabs.length || i == _tab) return;
    setState(() {
      _tab = i;
      _collapsed = false;
    });
    if (!restoreFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final last = _last[i];
      if (last != null && last.context != null && last.canRequestFocus) {
        last.requestFocus();
      } else {
        _tabNodes[i].traversalDescendants.where((n) => n.canRequestFocus).firstOrNull?.requestFocus();
      }
    });
  }

  bool _onScroll(ScrollNotification n) {
    // The grid's own scrolling only.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final px = n.metrics.pixels;
    final collapse = _collapsed ? px > 0.5 : px > _hideAt && n.metrics.maxScrollExtent > _headerHeight + _hideAt;
    if (collapse != _collapsed) setState(() => _collapsed = collapse);
    return false;
  }

  List<Hint> get _hints => [
    if (_tab == 0) ...[
      Hint(GameAction.confirm, tr('Open')),
      Hint(GameAction.favorite, tr('Favourite')),
      Hint(GameAction.detail, tr('A–Z')),
    ],
    if (_tab == 1) Hint(GameAction.confirm, tr('Get missing')),
    if (_tab == 2) Hint(GameAction.confirm, tr('Change')),
    Hint(GameAction.l1, tr('Previous tab')),
    Hint(GameAction.r1, tr('Next tab')),
    Hint(GameAction.back, tr('Back')),
  ];

  Widget _tabBody(int i) {
    final p = widget.platform;
    final child = switch (i) {
      0 => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: GalleryView(
          query: GalleryQuery(platformId: p.id),
          filterHint: tr('Filter this platform…'),
          pinnedBar: true,
        ),
      ),
      1 => FirmwareTab(platform: p),
      _ => EmulatorTab(platform: p),
    };
    // Every tab stays built (its games, its scroll); only the shown one takes focus.
    return ExcludeFocus(
      excluding: i != _tab,
      child: Focus(focusNode: _tabNodes[i], child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.platform;
    return Actions(
      actions: {
        PrevTabIntent: CallbackAction<PrevTabIntent>(onInvoke: (_) => _go(_tab - 1)),
        NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) => _go(_tab + 1)),
        MenuIntent: CallbackAction<MenuIntent>(onInvoke: (_) => openUserMenu(context, ref)),
      },
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
                        ? const SizedBox(width: double.infinity)
                        : PlatformHeader(key: const ValueKey('platform-header'), platform: p),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s2, GSpace.rowPad, 0),
                    child: Row(
                      children: [
                        if (_collapsed) ...[
                          Flexible(
                            child: Text(
                              p.nameForDisplay,
                              key: const ValueKey('platform-pinned-name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: GSpace.s5),
                        ],
                        Expanded(
                          child: GameTabs(
                            tabs: PlatformScreen.tabs,
                            index: _tab,
                            onTab: (i) => _go(i, restoreFocus: false),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _tab,
                      children: [for (var i = 0; i < PlatformScreen.tabs.length; i++) _tabBody(i)],
                    ),
                  ),
                  HintBar(hints: _hints),
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
