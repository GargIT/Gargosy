import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/platform/shortcut_maker.dart';
import '../../../core/romm/romm_models.dart';
import '../../../library/game_shortcut.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/library_providers.dart';
import '../../widgets/romm_images.dart';
import '../../widgets/toast.dart';
import '../../../l10n/tr.dart';

/// The program a shortcut starts: this Gargosy; tests replace it.
final appExecutableProvider = Provider<String>((ref) => io.Platform.resolvedExecutable);

/// The game page's ⋯ → Create desktop shortcut (#223): [game] in the open
/// profile, its cover as the icon when it can be read; says where it went.
Future<void> makeGameShortcut(BuildContext context, WidgetRef ref, Game game) async {
  final active = ref.read(activeProfileProvider);
  if (active == null) return;
  Uint8List? icon;
  final url = coverUrlFor(ref, game);
  if (url != null) {
    try {
      final file = await ref.read(rommImageCacheProvider).getSingleFile(url);
      icon = await squareIconPng(await file.readAsBytes());
    } on Object catch (e) {
      debugPrint('[Shortcut] no icon from the cover: $e');
    }
  }
  try {
    final link = await createGameShortcut(
      game: game,
      profile: active.paths,
      maker: ref.read(shortcutMakerProvider),
      exe: ref.read(appExecutableProvider),
      iconPng: icon,
    );
    if (context.mounted) showToast(context, tr('Shortcut made on the desktop: {0}', [p.basename(link)]));
  } on Object catch (e) {
    debugPrint('[Shortcut] ${game.displayName}: $e');
    if (context.mounted) showToast(context, tr('The shortcut couldn\'t be made: {0}', [e]));
  }
}
