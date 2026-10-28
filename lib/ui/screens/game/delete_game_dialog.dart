import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/input/gamepad_service.dart';
import '../../../core/romm/romm_models.dart';
import '../../../core/romm/romm_service.dart';
import '../../../play/play_controller.dart';
import '../../../providers/download_providers.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/romm_providers.dart';
import '../../../providers/ui_provider.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/hint_bar.dart';
import '../../widgets/toast.dart';
import '../../../l10n/tr.dart';

/// What the delete prompt asked for: the file on RomM's server too, the copy
/// on this PC too.
typedef GameDeletion = ({bool serverFile, bool thisPc});

/// The game page's ⋯ → Delete from RomM: asks ([showDeleteGame]), deletes it
/// on RomM, then its copy here when asked, and leaves the page. Only offered
/// to a RomM user who may delete games ([canDeleteGamesProvider]).
Future<void> deleteGameFromRomm(BuildContext context, WidgetRef ref, Game game, {required bool downloaded}) async {
  if (ref.read(playControllerProvider).runningGameId == game.id) {
    showToast(context, tr('Close the game first.'));
    return;
  }
  final romId = int.tryParse(game.id);
  final romm = ref.read(rommServiceProvider);
  if (romId == null || romm == null) {
    showToast(context, tr('Can\'t reach RomM.'));
    return;
  }
  final asked = await showDeleteGame(context, game, downloaded: downloaded);
  if (asked == null || !context.mounted) return;
  // The page rebuilds as the game goes from the caches: the navigator and
  // the provider container outlive it.
  final nav = Navigator.of(context);
  final container = ProviderScope.containerOf(context);
  final result = await romm.deleteGame(romId, fromServerDisk: asked.serverFile);
  if (!nav.mounted) return;
  switch (result) {
    case RomDeleteResult.notAllowed:
      await showNotice(
        nav.context,
        title: tr('RomM didn\'t allow it'),
        body: tr(
          'Either this RomM user may not delete games, or this profile signed in before Gargosy asked RomM for that. Sign in again under Settings → Profile → RomM account, then try again.',
        ),
      );
      return;
    case RomDeleteResult.failed:
      showToast(nav.context, tr('Couldn\'t delete it on RomM. Try again later.'));
      return;
    case RomDeleteResult.deleted:
      break;
  }
  if (asked.thisPc && downloaded) await container.read(downloadsProvider.notifier).delete(game);
  container.read(deletedGameIdsProvider.notifier).update((s) => {...s, game.id});
  for (final p in [recentlyAddedProvider, recentlyPlayedProvider, favouriteGamesProvider, randomGameProvider]) {
    container.invalidate(p);
  }
  container.invalidate(platformsProvider);
  container.invalidate(gameProvider(game.id));
  if (!nav.mounted) return;
  showToast(nav.context, tr('Deleted {0} from RomM.', [game.displayName]));
  nav.maybePop();
}

/// The prompt: what goes and that it can't be undone, the server's file and
/// this PC's copy as choices (both on), Cancel focused, and Delete only when
/// held (hold A, hold Enter, a long press). Null when cancelled.
Future<GameDeletion?> showDeleteGame(BuildContext context, Game game, {required bool downloaded}) =>
    showDialog<GameDeletion>(
      context: context,
      builder: (_) => _DeleteGameDialog(game: game, downloaded: downloaded),
    );

class _DeleteGameDialog extends ConsumerStatefulWidget {
  const _DeleteGameDialog({required this.game, required this.downloaded});

  final Game game;
  final bool downloaded;

  @override
  ConsumerState<_DeleteGameDialog> createState() => _DeleteGameDialogState();
}

class _DeleteGameDialogState extends ConsumerState<_DeleteGameDialog> {
  bool _serverFile = true;
  late bool _thisPc = widget.downloaded;

  /// Delete was pressed, not held: say how.
  bool _pressed = false;

  Widget _check(String key, String label, String note, bool on, VoidCallback onToggle) => GFocusable(
    key: ValueKey(key),
    borderRadius: GRadius.md,
    onActivate: onToggle,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s2, vertical: GSpace.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(on ? Icons.check_box : Icons.check_box_outline_blank, color: on ? GColors.primary : GColors.fgMuted),
          const SizedBox(width: GSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  note,
                  style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final others = game.siblings.length;
    final mode = ref.watch(inputModeProvider);
    final hold = switch (mode) {
      InputMode.gamepad => tr('Hold A to delete.'),
      InputMode.keyboard => tr('Hold Enter to delete.'),
      InputMode.mouse => tr('Press and hold to delete.'),
    };
    return Center(
      child: Material(
        color: GColors.panel,
        borderRadius: BorderRadius.circular(GRadius.lg),
        child: SizedBox(
          width: 520,
          child: Padding(
            padding: const EdgeInsets.all(GSpace.s5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Delete {0} from RomM?', [game.displayName]),
                  style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: GSpace.s3),
                Text(
                  tr(
                    'This is permanent and can\'t be undone. The game leaves RomM\'s library for every player, and everyone\'s saves and states of it on RomM go with it.{0}',
                    [
                      others == 0
                          ? ''
                          : ' Only this version${game.fsName == null ? '' : ' (${game.fsName})'} goes; '
                                'its ${others == 1 ? 'other version stays' : '$others other versions stay'}.',
                    ],
                  ),
                  style: const TextStyle(color: GColors.fgSecondary),
                ),
                const SizedBox(height: GSpace.s4),
                _check(
                  'delete-server-file',
                  tr('Also delete the file on the server'),
                  tr('Without it, RomM\'s next scan adds the game back.'),
                  _serverFile,
                  () => setState(() => _serverFile = !_serverFile),
                ),
                if (widget.downloaded)
                  _check(
                    'delete-this-pc',
                    tr('Also delete it from this PC'),
                    tr('Your saves on this PC are kept.'),
                    _thisPc,
                    () => setState(() => _thisPc = !_thisPc),
                  ),
                const SizedBox(height: GSpace.s4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        hold,
                        style: TextStyle(
                          fontSize: GFont.sm,
                          color: _pressed ? GColors.accent : GColors.fgMuted,
                          fontWeight: _pressed ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                    GFocusable(
                      key: const ValueKey('delete-cancel'),
                      autofocus: true,
                      borderRadius: GRadius.pill,
                      onActivate: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
                        decoration: BoxDecoration(
                          color: GColors.surface,
                          borderRadius: BorderRadius.circular(GRadius.pill),
                        ),
                        child: Text(tr('Cancel'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: GSpace.s2),
                    GFocusable(
                      key: const ValueKey('delete-confirm'),
                      borderRadius: GRadius.pill,
                      onActivate: () => setState(() => _pressed = true),
                      onLongActivate: () =>
                          Navigator.of(context).pop((serverFile: _serverFile, thisPc: widget.downloaded && _thisPc)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s2),
                        decoration: BoxDecoration(
                          color: GColors.dangerFill,
                          borderRadius: BorderRadius.circular(GRadius.pill),
                        ),
                        child: Text(
                          tr('Delete'),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: GColors.fg),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GSpace.s3),
                HintBar(
                  hints: [
                    Hint(GameAction.confirm, tr('Select')),
                    Hint(GameAction.confirmHold, tr('Delete')),
                    Hint(GameAction.back, tr('Cancel')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
