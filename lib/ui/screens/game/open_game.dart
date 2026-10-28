import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../library/game_versions.dart';
import '../../../library/library_snapshot.dart';
import '../../../providers/library_providers.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/toast.dart';
import 'game_screen.dart';
import '../../../l10n/tr.dart';

Future<void> openGame(BuildContext context, Game game) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(game: game)));

/// A folded card (#95): the version on this PC when only one is; asked when
/// more are ("Which version?"); RomM's own pick when none is (its page can
/// switch to another version).
Future<void> openGameVersion(BuildContext context, WidgetRef ref, Game game) async {
  if (game.siblings.isEmpty) return openGame(context, game);
  final onPc = {for (final g in ref.read(gamesOnThisPcProvider)) g.id};
  final here = [
    for (final v in allVersions(game))
      if (onPc.contains(v.id)) v,
  ];
  GameVersion? pick;
  if (here.length == 1) {
    pick = here.single;
  } else if (here.length > 1) {
    final i = await showChoice(
      context,
      title: tr('Which version?'),
      labels: [for (final v in here) versionLabel(v.name, v.fsNameNoExt)],
    );
    if (i == null || !context.mounted) return;
    pick = here[i];
  }
  if (pick == null || pick.id == game.id) return openGame(context, game);
  final other = await gameOfVersion(ref, pick.id);
  if (!context.mounted) return;
  if (other == null) {
    showToast(context, tr('Couldn\'t open that version.'));
    return;
  }
  return openGame(context, other);
}

/// Another version as a game: from RomM, else as it was downloaded.
Future<Game?> gameOfVersion(WidgetRef ref, String id) async {
  try {
    return await ref.read(gameProvider(id).future);
  } on Object {
    return null;
  }
}
