import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/storage/logger_service.dart';
import 'profiles/profile_providers.dart';
import 'providers/update_providers.dart';
import 'update/update_installer.dart';
import 'ui/input/gargosy_intents.dart';
import 'ui/input/input_router.dart';
import 'ui/screens/profile_picker_screen.dart';
import 'ui/shell/app_shell.dart';
import 'ui/shell/user_menu.dart';
import 'ui/theme/gargosy_theme.dart';
import 'ui/widgets/controller_dialogs.dart';

class GargosyApp extends ConsumerStatefulWidget {
  const GargosyApp({super.key, this.startGamepads = true});

  final bool startGamepads;

  @override
  ConsumerState<GargosyApp> createState() => _GargosyAppState();
}

class _GargosyAppState extends ConsumerState<GargosyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // One check per start (none within 6 h of the last); a find shows as a dot, never a popup.
      ref.read(updateStateProvider.notifier).startupCheck();
      final outcome = ref.read(updateOutcomeProvider);
      final nav = _navigatorKey.currentContext;
      if (outcome is UpdateFailed && nav != null) {
        showNotice(nav,
            title: "The update couldn't be installed",
            body: '${outcome.detail ?? 'The updater stopped.'}\n\nThis version is the one that runs; nothing was lost.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeProfileProvider);
    ref.listen(activeProfileProvider, (prev, next) {
      final tag = next == null ? null : LoggerService.shortId(next.profile.id);
      if (tag != LoggerService.profileTag) {
        // Closed under the old tag, opened under the new one.
        if (tag == null) debugPrint('[Profile] closed');
        LoggerService.profileTag = tag;
        if (tag != null) debugPrint('[Profile] opened $tag');
      }
      // A profile switch drops every page pushed on top (add profile, login).
      if ((prev == null) != (next == null)) _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    });
    return MaterialApp(
      title: 'Gargosy',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: gargosyTheme(),
      builder: (context, child) => InputRouter(
        navigatorKey: _navigatorKey,
        startGamepads: widget.startGamepads,
        child: Actions(
          actions: {
            ToggleFullscreenIntent: CallbackAction<ToggleFullscreenIntent>(
                onInvoke: (_) => toggleFullscreenAndRemember(ref.read(appPreferencesProvider).setBool)),
          },
          child: child!,
        ),
      ),
      home: active == null ? const ProfilePickerScreen() : const AppShell(),
    );
  }
}
