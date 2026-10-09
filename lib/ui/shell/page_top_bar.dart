import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profiles/profile_providers.dart';
import 'shell_menu.dart';
import 'top_bar.dart';

/// The top bar on pages opened over the shell (the game page, the gallery),
/// as RomM's v2 keeps it: no tab lit; a tab closes the opened pages and
/// shows that tab; the profile badge opens the user menu.
class PageTopBar extends ConsumerWidget {
  const PageTopBar({super.key, required this.scrolled});

  /// The page has scrolled: the bar turns to glass.
  final bool scrolled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = ref.watch(activeProfileProvider);
    if (ctx == null) return const SizedBox.shrink();
    return TopBar(
      tabs: shellTabs,
      index: null,
      scrolled: scrolled,
      context_: ctx,
      onMenu: () => openUserMenu(context, ref),
      onTab: (i) {
        ref.read(shellTabProvider.notifier).state = i;
        Navigator.of(context).popUntil((r) => r.isFirst);
      },
    );
  }
}
