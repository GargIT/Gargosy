import 'dart:ui';

import 'package:flutter/material.dart';

import '../../profiles/profile_providers.dart';
import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';
import '../widgets/profile_badge.dart';

/// v2's AppNav: the logo, a centred pill of tabs and the profile badge. The
/// bar is clear at the top of a page and glass once it scrolls (spec §7).
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onTab,
    required this.scrolled,
    required this.context_,
    required this.onMenu,
    this.tabFocusNodes,
  });

  final List<String> tabs;
  /// The lit tab; null on pages opened over the shell (none lit).
  final int? index;
  final ValueChanged<int> onTab;
  final bool scrolled;
  final ProfileContext context_;
  final VoidCallback onMenu;
  final List<FocusNode>? tabFocusNodes;

  @override
  Widget build(BuildContext context) {
    final bar = SizedBox(
      height: GLayout.navHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s6),
        child: Row(children: [
          Image.asset('assets/branding/gargosy_logo.png', key: const Key('top-bar-logo'), width: 32, height: 32),
          const SizedBox(width: GSpace.s2),
          const Text('Gargosy', style: TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            height: GLayout.navPillHeight,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
            child: Row(children: [
              for (var i = 0; i < tabs.length; i++)
                GFocusable(
                  focusNode: tabFocusNodes?[i],
                  autofocus: i == index,
                  borderRadius: GRadius.pill,
                  onActivate: () => onTab(i),
                  child: AnimatedContainer(
                    key: i == index ? const Key('top-bar-tab-lit') : null,
                    duration: GMotion.fast,
                    padding: const EdgeInsets.symmetric(horizontal: GSpace.s4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? GColors.fg : null,
                      borderRadius: BorderRadius.circular(GRadius.pill),
                    ),
                    child: Text(tabs[i],
                        style: TextStyle(
                          fontSize: GFont.md,
                          fontWeight: FontWeight.w600,
                          color: i == index ? GColors.bg : GColors.fgSecondary,
                        )),
                  ),
                ),
            ]),
          ),
          const Spacer(),
          ProfileBadge(
            profile: context_.profile,
            avatarPath: context_.paths.avatarFile,
            size: 34,
            showName: false,
            onActivate: onMenu,
          ),
        ]),
      ),
    );
    if (!scrolled) return bar;
    return ClipRect(
      key: const Key('top-bar-glass'),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xB307070F),
            border: Border(bottom: BorderSide(color: GColors.border)),
          ),
          child: bar,
        ),
      ),
    );
  }
}
