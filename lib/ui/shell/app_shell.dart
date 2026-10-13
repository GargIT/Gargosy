import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

export 'shell_menu.dart' show shellTabs, shellTabProvider;

import '../../changelog/whats_new.dart';
import '../../core/constants/app_constants.dart';
import '../../core/input/gamepad_service.dart';
import '../../library/upload_queue.dart';
import '../../providers/romm_providers.dart';
import '../../profiles/profile_providers.dart';
import '../input/gargosy_intents.dart';
import '../pages/collections_page.dart';
import '../pages/home_page.dart';
import '../pages/platforms_page.dart';
import '../pages/search_page.dart';
import '../screens/doc_reader_screen.dart';
import '../theme/tokens.dart';
import '../widgets/hint_bar.dart';
import '../widgets/toast.dart';
import 'backdrop.dart';
import 'shell_menu.dart';
import 'top_bar.dart';

/// The signed-in app: v2's top bar over the current tab's page (spec §7).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _scrolled = false;
  final _tabNodes = [for (final t in shellTabs) FocusNode(debugLabel: 'tab-$t')];

  @override
  void dispose() {
    for (final n in _tabNodes) {
      n.dispose();
    }
    super.dispose();
  }

  int get _index => ref.read(shellTabProvider);

  void _go(int i) {
    if (i < 0 || i >= shellTabs.length) return;
    ref.read(shellTabProvider.notifier).state = i;
    setState(() => _scrolled = false);
    _tabNodes[i].requestFocus();
  }

  Future<void> _menu() => openUserMenu(context, ref);

  @override
  void initState() {
    super.initState();
    // Saves left waiting by an earlier session go up when the profile opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _upload();
      _whatsNew();
    });
  }

  /// The first start of a newer version: its changelog since the last one
  /// that ran, once (issue #3). After an in-app update this is the only
  /// thing that opens; About keeps its quiet "Updated from" line.
  Future<void> _whatsNew() async {
    final root = ref.read(appRootProvider);
    final text = await whatsNewToShow(ref.read(appPreferencesProvider), AppConstants.version, readChangelog: () {
      final f = io.File(p.join(root.root, 'CHANGELOG.md'));
      return f.existsSync() ? f.readAsStringSync() : null;
    });
    if (text == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DocReaderScreen.text(
            title: "What's new in ${AppConstants.version.split('+').first}", text: text, baseDir: root.root)));
  }

  Future<void> _upload() async {
    final queue = await ref.read(uploadQueueProvider.future);
    if (queue == null || !mounted) return;
    final n = await queue.run();
    if (!mounted) return;
    ref.read(uploadQueueVersionProvider.notifier).state++;
    if (n > 0) showToast(context, n == 1 ? 'Uploaded 1 save that was waiting.' : 'Uploaded $n saves that were waiting.');
  }

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(activeProfileProvider);
    if (ctx == null) return const SizedBox.shrink();
    final index = ref.watch(shellTabProvider);
    // A page's top bar chose a tab: its focus follows.
    ref.listen<int>(shellTabProvider, (_, i) {
      if (mounted) setState(() => _scrolled = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && i < _tabNodes.length) _tabNodes[i].requestFocus();
      });
    });
    final offline = ref.watch(rommOfflineProvider);
    // RomM is back: what waited goes up.
    ref.listen<bool>(rommOfflineProvider, (was, now) {
      if (was == true && !now) _upload();
    });
    final pages = [
      HomePage(name: ctx.profile.name),
      const PlatformsPage(),
      const CollectionsPage(),
      const SearchPage(),
    ];
    return Actions(
      actions: {
        PrevTabIntent: CallbackAction<PrevTabIntent>(onInvoke: (_) => _go(_index - 1)),
        NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) => _go(_index + 1)),
        MenuIntent: CallbackAction<MenuIntent>(onInvoke: (_) => _menu()),
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Backdrop(
          child: Stack(children: [
            NotificationListener<ScrollNotification>(
              onNotification: (n) {
                // Only the page scrolling down counts, not a shelf scrolled sideways.
                if (n.metrics.axis != Axis.vertical) return false;
                final s = n.metrics.pixels > 8;
                if (s != _scrolled) setState(() => _scrolled = s);
                return false;
              },
              child: IndexedStack(index: index, children: pages),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: TopBar(
                tabs: shellTabs,
                index: index,
                onTab: _go,
                scrolled: _scrolled,
                context_: ctx,
                onMenu: _menu,
                tabFocusNodes: _tabNodes,
              ),
            ),
            if (offline)
              Positioned(
                left: 0,
                right: 0,
                top: GLayout.navHeight,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: GSpace.s2),
                    padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s2),
                    decoration: BoxDecoration(
                        color: GColors.accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(GRadius.pill)),
                    child: const Text(
                        "RomM can't be reached. Games on this PC still play; saves upload when it's back.",
                        style: TextStyle(color: GColors.accent, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            const Positioned(
              left: 0,
              bottom: 0,
              child: HintBar(hints: [
                Hint(GameAction.l1, 'Previous tab'),
                Hint(GameAction.r1, 'Next tab'),
                Hint(GameAction.start, 'Menu'),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
