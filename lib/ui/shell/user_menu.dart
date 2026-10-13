import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/platform/window_service.dart';
import '../../profiles/profile.dart';
import '../screens/settings/settings_pages.dart';
import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';
import '../widgets/profile_badge.dart';

/// The menu's own items, beside the settings sections.
enum UserMenuAction { fullscreen, changelog, switchProfile }

/// What the user menu picked: a section of Settings, or one of its actions.
class UserMenuChoice {
  const UserMenuChoice.settings(SettingsPage this.page) : action = null;
  const UserMenuChoice.action(UserMenuAction this.action) : page = null;

  final SettingsPage? page;
  final UserMenuAction? action;

  @override
  bool operator ==(Object other) => other is UserMenuChoice && other.page == page && other.action == action;

  @override
  int get hashCode => Object.hash(page, action);
}

/// The user menu (Start, or the profile badge), as RomM v2's: the profile
/// with Gargosy's version beside its name, every section of Settings in its
/// group (one item each, from [SettingsPage]), Fullscreen, About and the
/// changelog, and Switch profile at the bottom (RomM's Logout). [update]
/// ("Update available: 0.2.0") is an item of its own that opens About.
/// Focus starts on Profile; the menu scrolls when the window is short.
Future<UserMenuChoice?> showUserMenu(BuildContext context,
    {required Profile profile, String? avatarPath, String? update}) {
  Widget item(BuildContext c, String label, IconData icon, UserMenuChoice choice,
          {bool autofocus = false, Widget? trailing, Color? color, String? id}) =>
      GFocusable(
        key: ValueKey('user-menu-${id ?? choice.page?.name ?? choice.action!.name}'),
        autofocus: autofocus,
        borderRadius: GRadius.chip,
        onActivate: () => Navigator.of(c).pop(choice),
        child: SizedBox(
          height: 37,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GSpace.s3),
            child: Row(children: [
              Icon(icon, size: 17, color: color ?? GColors.fgSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w600, color: color ?? GColors.fg)),
              ),
              ?trailing,
            ]),
          ),
        ),
      );
  Widget heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(GSpace.s3, 14, GSpace.s3, 6),
        child: Text(text,
            style: const TextStyle(fontSize: GFont.xs, fontWeight: FontWeight.w700, letterSpacing: 1, color: GColors.fgSecondary)),
      );
  const line = Padding(
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: GSpace.s2),
    child: Divider(height: 1, thickness: 1, color: GColors.border),
  );
  final host = Uri.tryParse(profile.serverUrl)?.host ?? profile.serverUrl;
  return showDialog<UserMenuChoice>(
    context: context,
    builder: (c) => Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: GLayout.navHeight, right: GSpace.s6, bottom: GSpace.s4),
        child: Material(
          color: GColors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GRadius.lg),
            side: const BorderSide(color: GColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 282,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(GSpace.s2, 6, GSpace.s2, GSpace.s2),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, GSpace.s3, 10, 14),
                  child: Row(children: [
                    ProfileAvatar(profile: profile, avatarPath: avatarPath, size: 36),
                    const SizedBox(width: GSpace.s3),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(profile.name,
                                style: const TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: GSpace.s2),
                          Text('v${AppConstants.version}',
                              style: const TextStyle(fontSize: GFont.xs, color: GColors.fgSecondary)),
                        ]),
                        const SizedBox(height: 1),
                        Text('${profile.rommUsername} · $host',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgSecondary)),
                      ]),
                    ),
                  ]),
                ),
                const Divider(height: 1, thickness: 1, color: GColors.border, indent: 6, endIndent: 6),
                // Every section of Settings, one item each, in its groups.
                for (final group in SettingsGroup.values.where((g) => g != SettingsGroup.gargosy)) ...[
                  heading(group.heading),
                  for (final page in SettingsPage.values.where((p) => p.group == group))
                    item(c, page.label, page.icon, UserMenuChoice.settings(page), autofocus: page == SettingsPage.values.first),
                  if (group == SettingsGroup.thisPc)
                    item(c, 'Fullscreen', Icons.fullscreen, const UserMenuChoice.action(UserMenuAction.fullscreen),
                        trailing: const _KeyChip('F11')),
                ],
                line,
                if (update != null)
                  item(c, update, Icons.system_update_alt, const UserMenuChoice.settings(SettingsPage.about),
                      color: GColors.primaryHover, id: 'update'),
                for (final page in SettingsPage.values.where((p) => p.group == SettingsGroup.gargosy))
                  item(c, page.label, page.icon, UserMenuChoice.settings(page)),
                item(c, 'Changelog', Icons.history, const UserMenuChoice.action(UserMenuAction.changelog)),
                line,
                item(c, 'Switch profile', Icons.swap_horiz, const UserMenuChoice.action(UserMenuAction.switchProfile),
                    color: GColors.danger),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A small key name beside an item, as RomM marks Beta.
class _KeyChip extends StatelessWidget {
  const _KeyChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: GColors.primary.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(GRadius.sm),
        ),
        child: Text(text, style: const TextStyle(fontSize: GFont.xs, fontWeight: FontWeight.w600, color: GColors.primaryHover)),
      );
}

/// F11 and the menu item: toggles fullscreen and remembers it (spec §7).
Future<void> toggleFullscreenAndRemember(Future<bool> Function(String key, bool value) save) async {
  await WindowService.toggleFullScreen();
  await save(WindowService.launchFullscreenPrefKey, await WindowService.isFullScreen());
}
