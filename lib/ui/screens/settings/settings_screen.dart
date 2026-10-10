import 'package:flutter/material.dart';

import '../../../core/input/gamepad_service.dart';
import '../../input/gargosy_intents.dart';
import '../../shell/backdrop.dart';
import '../../theme/tokens.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/hint_bar.dart';
import 'about_section.dart';
import 'device_sections.dart';
import 'emulators_section.dart';
import 'profile_section.dart';
import 'ra_section.dart';

/// Settings (spec §2): Profile, Controller, Display, Emulators and
/// RetroAchievements. The sections on the left, the chosen one on the
/// right; LB/RB move between sections, B goes back.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _sections = ['Profile', 'Controller', 'Display', 'Emulators', 'RetroAchievements', 'About'];
  int _section = 0;

  Widget _content() => switch (_section) {
        0 => const ProfileSection(),
        1 => const ControllerSection(),
        2 => const DisplaySection(),
        3 => const EmulatorsSection(),
        4 => const RaSection(),
        _ => const AboutSection(),
      };

  void _go(int i) {
    if (i >= 0 && i < _sections.length) setState(() => _section = i);
  }

  @override
  Widget build(BuildContext context) => Actions(
        actions: {
          PrevTabIntent: CallbackAction<PrevTabIntent>(onInvoke: (_) => _go(_section - 1)),
          NextTabIntent: CallbackAction<NextTabIntent>(onInvoke: (_) => _go(_section + 1)),
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Backdrop(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s10, GSpace.rowPad, GSpace.s4),
                child: Text('Settings', style: TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: GSpace.rowPad),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 260,
                      child: Column(children: [
                        for (var i = 0; i < _sections.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: GSpace.s1),
                            child: GFocusable(
                              autofocus: i == 0,
                              borderRadius: GRadius.pill,
                              onActivate: () => _go(i),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
                                decoration: BoxDecoration(
                                  color: i == _section ? GColors.surfaceHover : Colors.transparent,
                                  borderRadius: BorderRadius.circular(GRadius.pill),
                                ),
                                child: Text(_sections[i],
                                    style: TextStyle(
                                        fontSize: GFont.lg,
                                        fontWeight: FontWeight.w700,
                                        color: i == _section ? GColors.fg : GColors.fgSecondary)),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(width: GSpace.s8),
                    Expanded(child: KeyedSubtree(key: ValueKey(_section), child: _content())),
                  ]),
                ),
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
