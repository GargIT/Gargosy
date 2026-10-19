import 'package:flutter/material.dart';

import '../../sigil/sigil_library.dart';
import '../theme/gargosy_theme.dart';
import '../theme/tokens.dart';

/// Shown instead of Gargosy when it can't start: its folder can't be written
/// (spec §3; Gargosy never falls back to AppData), or sigil.dll won't load
/// (#57; saves never fall back to other code).
class StartupErrorApp extends StatelessWidget {
  /// The folder can't be written; [message] is the error and the path.
  const StartupErrorApp({super.key, required this.message})
    : title = "Gargosy can't write to its folder",
      advice =
          'Gargosy keeps everything next to Gargosy.exe. Move the Gargosy folder somewhere you can write to '
          r'(for example D:\Games\Gargosy, not C:\Program Files) and start it again.';

  /// sigil.dll, which reads and writes the saves, can't be used.
  factory StartupErrorApp.sigil(SigilUnavailable e, {Key? key}) => StartupErrorApp._(
    key: key,
    title: "Gargosy can't load sigil.dll",
    message: '$e',
    advice:
        'Gargosy syncs saves through sigil.dll, which comes with Gargosy beside Gargosy.exe. '
        'Unpack the whole Gargosy zip again over this folder (your profiles, ROMs and emulators stay) '
        'and start it again.',
  );

  const StartupErrorApp._({super.key, required this.title, required this.message, required this.advice});

  final String title;
  final String message;
  final String advice;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: gargosyTheme(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: GFont.xxxl, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: GSpace.s4),
                Text(
                  message,
                  style: const TextStyle(fontSize: GFont.lg, color: GColors.fgSecondary),
                ),
                const SizedBox(height: GSpace.s4),
                Text(advice, style: const TextStyle(fontSize: GFont.lg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
