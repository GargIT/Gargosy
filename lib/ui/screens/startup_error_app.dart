import 'package:flutter/material.dart';

import '../theme/gargosy_theme.dart';
import '../theme/tokens.dart';

/// Shown instead of Gargosy when its folder can't be written (spec §3).
/// Gargosy never falls back to AppData.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: gargosyTheme(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Gargosy can't write to its folder", style: TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800)),
              const SizedBox(height: GSpace.s4),
              Text(message, style: const TextStyle(fontSize: GFont.lg, color: GColors.fgSecondary)),
              const SizedBox(height: GSpace.s4),
              const Text(
                'Gargosy keeps everything next to Gargosy.exe. Move the Gargosy folder somewhere you can write to '
                r'(for example D:\Games\Gargosy, not C:\Program Files) and start it again.',
                style: TextStyle(fontSize: GFont.lg),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
