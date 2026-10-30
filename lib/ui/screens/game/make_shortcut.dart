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
import '../../../providers/update_providers.dart';
import '../../widgets/romm_images.dart';
import '../../widgets/toast.dart';
import '../../../l10n/tr.dart';

/// The game page's ⋯ → Create desktop shortcut (#223): [game] in the open
/// profile, its cover as the icon when it can be read; says where it went.
/// Everything it needs is read before the first wait, so leaving the page
/// meanwhile still makes it.
Future<void> makeGameShortcut(BuildContext context, WidgetRef ref, Game game) async {
  final active = ref.read(activeProfileProvider);
  if (active == null) return;
  final maker = ref.read(shortcutMakerProvider);
  final exe = ref.read(appExecutableProvider);
  final images = ref.read(rommImageCacheProvider);
  // The small cover: near the icon's size, and usually cached from a grid.
  final url = coverUrlFor(ref, game, small: true);
  Uint8List? icon;
  if (url != null) {
    try {
      icon = await squareIconPng(await (await images.getSingleFile(url)).readAsBytes());
    } on Object catch (e) {
      debugPrint('[Shortcut] no icon from the cover: $e');
    }
  }
  try {
    final link = await createGameShortcut(game: game, profile: active.paths, maker: maker, exe: exe, iconPng: icon);
    if (context.mounted) showToast(context, tr('Shortcut made on the desktop: {0}', [p.basename(link)]));
  } on Object catch (e) {
    debugPrint('[Shortcut] ${game.displayName}: $e');
    if (context.mounted) showToast(context, tr('The shortcut couldn\'t be made: {0}', [_short(e)]));
  }
}

/// The first line of why, without Dart's or PowerShell's wrapping.
String _short(Object e) {
  final text = (e is io.FileSystemException && e.message.isNotEmpty ? e.message : '$e').trim();
  final line = text.split('\n').first.trim();
  return line.length > 120 ? '${line.substring(0, 120)}…' : line;
}
