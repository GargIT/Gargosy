import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../library/download_service.dart';
import '../../../play/play_controller.dart';
import '../play/play_screen.dart';
import '../../../providers/download_providers.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/format.dart';
import '../../widgets/favourite.dart';
import '../../widgets/toast.dart';

/// The game page's actions: Download, or Play and Delete once downloaded, and
/// the favourite heart.
class GameActions extends ConsumerWidget {
  const GameActions({super.key, required this.game});

  final Game game;

  Widget _button(String label, IconData icon, VoidCallback? onPress, {bool autofocus = false, bool primary = false}) => GFocusable(
        autofocus: autofocus,
        borderRadius: GRadius.pill,
        onActivate: onPress,
        child: Container(
          width: 240,
          padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
          decoration: BoxDecoration(
            color: primary ? GColors.primary : GColors.surface,
            borderRadius: BorderRadius.circular(GRadius.pill),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20, color: onPress == null ? GColors.fgFaint : GColors.fg),
            const SizedBox(width: GSpace.s2),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700, color: onPress == null ? GColors.fgFaint : GColors.fg)),
            ),
          ]),
        ),
      );

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${game.displayName} from this PC?'),
        content: const Text('The ROM is removed from this PC only. It stays on RomM, and your saves are not touched.'),
        actions: [
          GFocusable(
            autofocus: true,
            borderRadius: GRadius.pill,
            onActivate: () => Navigator.of(c).pop(false),
            child: const Padding(padding: EdgeInsets.all(GSpace.s3), child: Text('Keep')),
          ),
          GFocusable(
            borderRadius: GRadius.pill,
            onActivate: () => Navigator.of(c).pop(true),
            child: const Padding(padding: EdgeInsets.all(GSpace.s3), child: Text('Delete', style: TextStyle(color: GColors.danger))),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(downloadsProvider.notifier).delete(game);
  }

  /// The play screen: choose the save and emulator, then start. What the
  /// player should know afterwards is told here, on the game page.
  Future<void> _play(BuildContext context, WidgetRef ref) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PlayScreen(game: game, onNotice: (m) {
          if (context.mounted) showToast(context, m);
        }),
      ));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(downloadsProvider)[game.id];
    final downloaded = watchDownloaded(ref, game);
    final isFavourite = ref.watch(favouriteIdsProvider).contains(game.id);
    final playing = ref.watch(playControllerProvider.select((s) => s.runningGameId == game.id));
    // When this game's session ends, say how its saves went.
    ref.listen(playControllerProvider, (prev, next) {
      if (prev?.runningGameId == game.id && next.runningGameId == null && next.message != null) {
        showToast(context, next.message!);
      }
    });
    final children = <Widget>[];
    if (progress != null && progress.phase != DownloadPhase.failed) {
      final pct = progress.fraction == null ? '' : ' ${(progress.fraction! * 100).round()} %';
      children.addAll([
        SizedBox(width: 240, child: LinearProgressIndicator(value: progress.fraction, color: GColors.primary)),
        const SizedBox(height: GSpace.s2),
        Text(progress.phase == DownloadPhase.extracting ? 'Unpacking…' : 'Downloading$pct',
            style: const TextStyle(color: GColors.fgSecondary)),
        // Unpacking can't be stopped halfway, so Cancel goes away once it starts.
        if (progress.phase == DownloadPhase.downloading) ...[
          const SizedBox(height: GSpace.s3),
          _button('Cancel', Icons.close, () => ref.read(downloadsProvider.notifier).cancel(game.id), autofocus: true),
        ],
      ]);
    } else if (downloaded) {
      children.addAll([
        _button(playing ? 'Playing…' : 'Play', Icons.play_arrow, playing ? null : () => _play(context, ref),
            autofocus: true, primary: true),
        const SizedBox(height: GSpace.s3),
        _button('Delete from this PC', Icons.delete_outline, () => _confirmDelete(context, ref)),
      ]);
    } else {
      final size = game.fileSize > 0 ? ' (${formatBytes(game.fileSize)})' : '';
      children.add(_button('Download$size', Icons.download, () => ref.read(downloadsProvider.notifier).start(game),
          autofocus: true, primary: true));
      if (progress?.phase == DownloadPhase.failed) {
        children.addAll([
          const SizedBox(height: GSpace.s2),
          SizedBox(
            width: 240,
            child: Text('The download failed: ${progress!.error}', style: const TextStyle(color: GColors.danger, fontSize: GFont.sm)),
          ),
        ]);
      }
    }
    children.addAll([
      const SizedBox(height: GSpace.s3),
      _button(isFavourite ? 'Favourite' : 'Add to favourites', isFavourite ? Icons.favorite : Icons.favorite_border,
          () => favourite(context, ref, game)),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.center, children: children);
  }
}
