import 'package:flutter/material.dart';

import '../../../core/input/gamepad_service.dart';
import '../../input/gargosy_intents.dart';
import '../../shell/backdrop.dart';
import '../../shell/page_top_bar.dart';
import '../../theme/tokens.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/hint_bar.dart';
import 'about_section.dart';
import 'device_sections.dart';
import 'emulators_section.dart';
import 'profile_section.dart';
import 'ra_section.dart';
import 'settings_rows.dart';

/// The sidebar's groups, as RomM's profile page has them.
enum SettingsGroup {
  profile('PROFILE'),
  library('LIBRARY'),
  thisPc('THIS PC'),
  gargosy('GARGOSY');

  const SettingsGroup(this.heading);
  final String heading;
}

/// A section of Settings, in the sidebar's order. The user menu opens
/// Settings on one of them.
enum SettingsPage {
  profile(SettingsGroup.profile, 'Profile', Icons.person_outline),
  retroAchievements(SettingsGroup.profile, 'RetroAchievements', Icons.emoji_events_outlined),
  emulators(SettingsGroup.library, 'Emulators', Icons.videogame_asset_outlined),
  controller(SettingsGroup.thisPc, 'Controller', Icons.gamepad_outlined),
  display(SettingsGroup.thisPc, 'Display', Icons.desktop_windows_outlined),
  about(SettingsGroup.gargosy, 'About', Icons.info_outline);

  const SettingsPage(this.group, this.label, this.icon);
  final SettingsGroup group;
  final String label;
  final IconData icon;
}

/// Settings in RomM v2's style: the top bar, the sections in groups on the
/// left, the chosen one's cards on the right. LB/RB move between sections,
/// B goes back.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initial = SettingsPage.profile});

  final SettingsPage initial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsPage _page = widget.initial;

  Widget _content() => switch (_page) {
        SettingsPage.profile => const ProfileSection(),
        SettingsPage.retroAchievements => const RaSection(),
        SettingsPage.emulators => const EmulatorsSection(),
        SettingsPage.controller => const ControllerSection(),
        SettingsPage.display => const DisplaySection(),
        SettingsPage.about => ListView(children: const [
            SettingsCard(title: 'About', icon: Icons.info, children: [AboutSection()]),
          ]),
      };

  void _go(int i) {
    if (i >= 0 && i < SettingsPage.values.length) setState(() => _page = SettingsPage.values[i]);
  }

  Widget _item(SettingsPage page) {
    final current = page == _page;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GFocusable(
        key: ValueKey('settings-${page.name}'),
        autofocus: page == widget.initial,
        borderRadius: GRadius.sm,
        onActivate: () => setState(() => _page = page),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: current ? GColors.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(GRadius.sm),
          ),
          child: Row(children: [
            Icon(page.icon, size: 17, color: current ? GColors.fg : GColors.fgSecondary),
            const SizedBox(width: GSpace.s3),
            Flexible(
              child: Text(page.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: GFont.md, fontWeight: FontWeight.w600, color: current ? GColors.fg : GColors.fgSecondary)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sidebar() => Container(
        key: const Key('settings-sidebar'),
        width: 225,
        decoration: const BoxDecoration(border: Border(right: BorderSide(color: GColors.border))),
        child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: GSpace.s6), children: [
          for (final group in SettingsGroup.values) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(18, group == SettingsGroup.values.first ? 0 : GSpace.s5, 18, GSpace.s2),
              child: Text(group.heading,
                  style: const TextStyle(
                      fontSize: GFont.xs, fontWeight: FontWeight.w700, letterSpacing: 1, color: GColors.fgSecondary)),
            ),
            for (final page in SettingsPage.values)
              if (page.group == group) _item(page),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) => Actions(
        actions: {
          PrevTabIntent: CallbackAction<PrevTabIntent>(onInvoke: (_) => _go(_page.index - 1)),
          NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) => _go(_page.index + 1)),
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Backdrop(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const PageTopBar(scrolled: false),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _sidebar(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(GSpace.s10, GSpace.s7, GSpace.s10, 0),
                      child: KeyedSubtree(key: ValueKey(_page), child: _content()),
                    ),
                  ),
                ]),
              ),
              const HintBar(hints: [
                Hint(GameAction.confirm, 'Choose'),
                Hint(GameAction.l1, 'Previous'),
                Hint(GameAction.r1, 'Next'),
                Hint(GameAction.back, 'Back'),
              ]),
            ]),
          ),
        ),
      );
}
