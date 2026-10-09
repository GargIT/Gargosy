import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/gamepad_service.dart';
import '../../play/play_controller.dart';
import '../../profiles/profile_providers.dart';
import '../input/gargosy_intents.dart';
import '../pages/collections_page.dart';
import '../pages/home_page.dart';
import '../pages/platforms_page.dart';
import '../pages/search_page.dart';
import '../screens/emulators_screen.dart';
import '../widgets/hint_bar.dart';
import '../widgets/toast.dart';
import 'backdrop.dart';
import 'top_bar.dart';
import 'user_menu.dart';

const shellTabs = ['Home', 'Platforms', 'Collections', 'Search'];

/// The signed-in app: v2's top bar over the current tab's page (spec §7).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _scrolled = false;
  final _tabNodes = [for (final t in shellTabs) FocusNode(debugLabel: 'tab-$t')];

  @override
  void dispose() {
    for (final n in _tabNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _go(int i) {
    if (i < 0 || i >= shellTabs.length) return;
    setState(() {
      _index = i;
      _scrolled = false;
    });
    _tabNodes[i].requestFocus();
  }

  Future<void> _menu() async {
    final ctx = ref.read(activeProfileProvider);
    if (ctx == null) return;
    final choice = await showUserMenu(context, name: ctx.profile.name);
    switch (choice) {
      case UserMenuChoice.switchProfile:
        // The game runs on this profile's emulator data; it must close first.
        if (ref.read(playControllerProvider).runningGameId != null) {
          if (mounted) showToast(context, "Close the game first: a profile can't change while a game runs.");
          return;
        }
        ref.read(activeProfileProvider.notifier).signOut();
      case UserMenuChoice.emulators:
        if (mounted) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmulatorsScreen()));
      case UserMenuChoice.fullscreen:
        await toggleFullscreenAndRemember(ref.read(appPreferencesProvider).setBool);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(activeProfileProvider);
    if (ctx == null) return const SizedBox.shrink();
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
              child: IndexedStack(index: _index, children: pages),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: TopBar(
                tabs: shellTabs,
                index: _index,
                onTab: _go,
                scrolled: _scrolled,
                context_: ctx,
                onMenu: _menu,
                tabFocusNodes: _tabNodes,
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
