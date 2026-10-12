import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/storage/logger_service.dart';
import 'profiles/profile_providers.dart';
import 'ui/input/gargosy_intents.dart';
import 'ui/input/input_router.dart';
import 'ui/screens/profile_picker_screen.dart';
import 'ui/shell/app_shell.dart';
import 'ui/shell/user_menu.dart';
import 'ui/theme/gargosy_theme.dart';

class GargosyApp extends ConsumerStatefulWidget {
  const GargosyApp({super.key, this.startGamepads = true});

  final bool startGamepads;

  @override
  ConsumerState<GargosyApp> createState() => _GargosyAppState();
}

class _GargosyAppState extends ConsumerState<GargosyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeProfileProvider);
    ref.listen(activeProfileProvider, (prev, next) {
      final tag = next == null ? null : LoggerService.shortId(next.profile.id);
      if (tag != LoggerService.profileTag) {
        debugPrint(tag == null ? '[Profile] closed' : '[Profile] opened $tag');
        LoggerService.profileTag = tag;
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
