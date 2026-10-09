import 'package:flutter/material.dart';

import '../../core/input/gamepad_service.dart';
import '../../core/platform/window_service.dart';
import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';
import '../widgets/hint_bar.dart';

enum UserMenuChoice { switchProfile, emulators, fullscreen }

/// The user menu (Start, or the profile badge). Milestone A: switch profile
/// and fullscreen; settings arrive later.
Future<UserMenuChoice?> showUserMenu(BuildContext context, {required String name}) {
  Widget item(BuildContext c, String label, IconData icon, UserMenuChoice choice, {bool autofocus = false}) => GFocusable(
        autofocus: autofocus,
        borderRadius: GRadius.md,
        onActivate: () => Navigator.of(c).pop(choice),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
          child: Row(children: [
            Icon(icon, color: GColors.fgSecondary),
            const SizedBox(width: GSpace.s3),
            Flexible(child: Text(label, style: const TextStyle(fontSize: GFont.lg), overflow: TextOverflow.ellipsis)),
          ]),
        ),
      );
  return showDialog<UserMenuChoice>(
    context: context,
    builder: (c) => Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: GLayout.navHeight, right: GSpace.s6),
        child: Material(
          color: GColors.panel,
          borderRadius: BorderRadius.circular(GRadius.lg),
          child: SizedBox(
            width: 300,
            child: Padding(
              padding: const EdgeInsets.all(GSpace.s2),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.all(GSpace.s3),
                  child: Text(name, style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700)),
                ),
                item(c, 'Switch profile', Icons.people_alt_outlined, UserMenuChoice.switchProfile, autofocus: true),
                item(c, 'Emulators', Icons.videogame_asset_outlined, UserMenuChoice.emulators),
                item(c, 'Fullscreen (F11)', Icons.fullscreen, UserMenuChoice.fullscreen),
                const HintBar(hints: [Hint(GameAction.confirm, 'Select'), Hint(GameAction.back, 'Close')]),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
}

/// F11 and the menu item: toggles fullscreen and remembers it (spec §7).
Future<void> toggleFullscreenAndRemember(Future<bool> Function(String key, bool value) save) async {
  await WindowService.toggleFullScreen();
  await save(WindowService.launchFullscreenPrefKey, await WindowService.isFullScreen());
}
