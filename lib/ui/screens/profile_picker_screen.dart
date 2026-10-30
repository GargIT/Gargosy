import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/gamepad_service.dart';
import '../../play/outside_launch.dart';
import '../../profiles/pin.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_paths.dart';
import '../../profiles/profile_providers.dart';
import '../shell/backdrop.dart';
import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';
import '../widgets/hint_bar.dart';
import '../widgets/pin_pad.dart';
import '../widgets/profile_badge.dart';
import '../widgets/toast.dart';
import 'add_profile_screen.dart';
import 'login_step.dart';
import 'profile_options_dialog.dart';
import '../../l10n/tr.dart';

/// "Who is playing?": Plex-style badges, the last used one focused (spec §5).
class ProfilePickerScreen extends ConsumerStatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  ConsumerState<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends ConsumerState<ProfilePickerScreen> {
  final Map<String, bool> _hasLogin = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openForLaunch());
  }

  /// Started with `--play` (#223): its profile opens as if chosen, PIN and
  /// all. A profile that isn't there, a wrong PIN or Back ends here, and the
  /// launch is dropped: the game never starts behind the picker's back.
  Future<void> _openForLaunch() async {
    final launch = ref.read(outsideLaunchProvider);
    if (launch == null) return;
    final List<Profile> profiles;
    try {
      profiles = await ref.read(profilesProvider.future);
    } on Object {
      ref.read(outsideLaunchProvider.notifier).state = null;
      return;
    }
    if (!mounted) return;
    final p = launch.profileIn(profiles, ref.read(profileStoreProvider).lastUsedId);
    if (p == null) {
      ref.read(outsideLaunchProvider.notifier).state = null;
      showToast(context, tr('Choose who is playing, then start the game again.'));
      return;
    }
    await _open(p);
    // Opened, the shell has replaced this page and takes the launch.
    if (mounted && ref.read(activeProfileProvider) == null) ref.read(outsideLaunchProvider.notifier).state = null;
  }

  Future<void> _loadLogins(List<Profile> profiles) async {
    for (final p in profiles) {
      if (_hasLogin.containsKey(p.id)) continue;
      final login = await loginStoreForWidget(ref, p).read();
      if (mounted) setState(() => _hasLogin[p.id] = login != null);
    }
  }

  Future<bool> _unlock(Profile p) async {
    final pin = p.pin;
    if (pin == null) return true;
    final gate = ref.read(pinGatesProvider).putIfAbsent(p.id, () => PinGate(pin));
    final ok = await showPinEntry(
      context,
      title: tr('PIN for {0}', [p.name]),
      check: (entered) async {
        switch (await gate.attempt(entered)) {
          case PinResult.ok:
            return null;
          case PinResult.wrong:
            return tr('Wrong PIN');
          case PinResult.locked:
            return tr('Too many tries. Wait {0} seconds.', [gate.lockedFor?.inSeconds ?? 30]);
        }
      },
    );
    return ok != null;
  }

  Future<void> _open(Profile p) async {
    if (!await _unlock(p) || !mounted) return;
    final login = await loginStoreForWidget(ref, p).read();
    if (login != null) {
      await ref.read(activeProfileProvider.notifier).activate(p, login);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => Scaffold(
          body: LoginStep(
            serverUrl: p.serverUrl,
            trustSelfSigned: p.trustSelfSigned,
            deviceName: tr('Gargosy on {0}', [ref.read(pcIdentityProvider).machineName]),
            expectedUserId: p.rommUserId,
            expectedUsername: p.rommUsername,
            onBack: () => Navigator.of(routeContext).pop(),
            onLoggedIn: (login, me) async {
              await loginStoreForWidget(ref, p).write(ProfilePaths(ref.read(appRootProvider), p.id).guard, login);
              _hasLogin[p.id] = true;
              // GargosyApp pops this page when the profile becomes active.
              await ref.read(activeProfileProvider.notifier).activate(p, login);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _options(Profile p) async {
    final choice = await showProfileOptions(context, name: p.name);
    if (choice != ProfileOption.delete || !mounted) return;
    if (!await _unlock(p) || !mounted) return;
    if (!await confirmDeleteProfile(context, name: p.name)) return;
    await ref.read(profileStoreProvider).delete(p.id);
    ref.read(pinGatesProvider).remove(p.id);
    _hasLogin.remove(p.id);
    ref.invalidate(profilesProvider);
  }

  Future<void> _add(List<Profile> profiles) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddProfileScreen(suggestedServer: profiles.isEmpty ? '' : profiles.last.serverUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(profilesProvider);
    final lastUsed = ref.read(profileStoreProvider).lastUsedId;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Backdrop(
        child: profiles.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(tr('Profiles could not be read: {0}', [e]))),
          data: (list) {
            _loadLogins(list);
            final focusId = list.any((p) => p.id == lastUsed) ? lastUsed : (list.isEmpty ? null : list.first.id);
            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/branding/gargosy_logo.png', width: 180, height: 180),
                        const SizedBox(height: GSpace.s6),
                        Text(
                          tr('Who is playing?'),
                          style: const TextStyle(fontSize: GFont.xxxxl, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: GSpace.s10),
                        Wrap(
                          spacing: GSpace.s10,
                          runSpacing: GSpace.s8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final p in list)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ProfileBadge(
                                    profile: p,
                                    avatarPath: ProfilePaths(ref.read(appRootProvider), p.id).avatarFile,
                                    autofocus: p.id == focusId,
                                    onActivate: () => _open(p),
                                    onDetail: () => _options(p),
                                  ),
                                  if (_hasLogin[p.id] == false)
                                    Text(
                                      tr('Log in again'),
                                      style: const TextStyle(fontSize: GFont.sm, color: GColors.accent),
                                    ),
                                ],
                              ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GFocusable(
                                  autofocus: focusId == null,
                                  borderRadius: GRadius.pill,
                                  onActivate: () => _add(list),
                                  child: Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: GColors.borderStrong, width: 2),
                                    ),
                                    child: const Icon(Icons.add, size: 48, color: GColors.fgSecondary),
                                  ),
                                ),
                                const SizedBox(height: GSpace.s3),
                                GestureDetector(
                                  onTap: () => _add(list),
                                  child: Text(
                                    tr('Add profile'),
                                    style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                HintBar(hints: [Hint(GameAction.confirm, tr('Play')), Hint(GameAction.detail, tr('Options'))]),
              ],
            );
          },
        ),
      ),
    );
  }
}
