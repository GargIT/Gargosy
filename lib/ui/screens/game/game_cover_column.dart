import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../core/save/catalog/play_request.dart';
import '../../../library/disk_space.dart';
import '../../../library/download_service.dart';
import '../../../play/play_controller.dart';
import '../../../profiles/profile_providers.dart';
import '../../../play/play_engine.dart';
import '../../../play/save_actions.dart';
import '../../../providers/download_providers.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/romm_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/game_transition.dart';
import '../../widgets/outlined_back_button.dart';
import '../../widgets/favourite.dart';
import '../../widgets/format.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/toast.dart';
import '../play/play_screen.dart';
import 'add_to_collection.dart';
import 'delete_game_dialog.dart';
import 'make_shortcut.dart';
import '../../../l10n/tr.dart';

/// Opens a folder in Windows' Explorer; tests replace it.
final folderOpenerProvider = Provider<void Function(String path)>(
  (ref) => (path) {
    io.Process.start('explorer.exe', [path]);
  },
);

/// The game page's left column (spec Part 1): the cover; ▶ Play (Download,
/// the progress, Playing… as they apply); under it ♥ and ⋯. The cover is the
/// play screen's size, so it doesn't jump between the two.
class GameCoverColumn extends ConsumerWidget {
  const GameCoverColumn({super.key, required this.game});

  final Game game;

  static const coverWidth = 240.0;
  static const coverHeight = 324.0;

  Widget _wide(String label, IconData icon, VoidCallback? onPress, {bool primary = false, Key? key}) => GFocusable(
    key: key,
    autofocus: true,
    borderRadius: GRadius.pill,
    onActivate: onPress,
    child: Container(
      width: coverWidth,
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
      decoration: BoxDecoration(
        color: primary ? GColors.primary : GColors.surface,
        borderRadius: BorderRadius.circular(GRadius.pill),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: onPress == null ? GColors.fgFaint : GColors.fg),
          const SizedBox(width: GSpace.s2),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: GFont.lg,
                fontWeight: FontWeight.w700,
                color: onPress == null ? GColors.fgFaint : GColors.fg,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _small(Key key, Widget child, VoidCallback onPress) => Expanded(
    child: GFocusable(
      key: key,
      borderRadius: GRadius.pill,
      onActivate: onPress,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: GSpace.s3),
        decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.pill)),
        child: Center(child: child),
      ),
    ),
  );

  Future<void> _play(BuildContext context) => Navigator.of(context).push(
    fadeRoute<void>(
      PlayScreen(
        game: game,
        onNotice: (m) {
          if (context.mounted) showToast(context, m);
        },
      ),
    ),
  );

  Future<void> _more(BuildContext context, WidgetRef ref, bool downloaded) async {
    final engine = ref.read(playEngineProvider);
    final menu = ref.read(playMenuProvider(PlayMenuKey(game))).valueOrNull;
    final remembered = menu?.remembered;
    final items = <({String label, bool danger, Future<void> Function() run})>[
      if (ref.read(collectionEditsProvider) != null)
        (label: tr('Add to collection…'), danger: false, run: () => showAddToCollection(context, game)),
      if (downloaded)
        (
          label: tr('Open the game\'s folder'),
          danger: false,
          run: () async {
            final path = ref.read(romFilesProvider).pathFor(game);
            ref.read(folderOpenerProvider)(
              io.FileSystemEntity.isDirectorySync(path) ? path : io.File(path).parent.path,
            );
          },
        ),
      if (downloaded)
        (label: tr('Create desktop shortcut'), danger: false, run: () => makeGameShortcut(context, ref, game)),
      if (downloaded && (engine?.stateSyncAvailable(game) ?? false))
        (
          label: tr('Sync save states now'),
          danger: false,
          run: () async {
            final said = await ref.read(saveActionsProvider).syncStates(game);
            if (context.mounted && said.isNotEmpty) showToast(context, said);
          },
        ),
      if (remembered != null)
        (
          label: tr('Forget "Always in {0}"', [menu!.nameOf(remembered)]),
          danger: false,
          run: () async {
            await engine?.remember(game, PlayRequest(emulator: remembered, forget: true));
            ref.invalidate(playMenuProvider(PlayMenuKey(game)));
          },
        ),
      if (downloaded)
        (
          label: tr('Delete from this PC…'),
          danger: true,
          run: () async {
            final ok = await showConfirm(
              context,
              title: tr('Delete {0} from this PC?', [game.displayName]),
              body: tr('The ROM is removed from this PC only. It stays on RomM, and your saves are not touched.'),
              yes: tr('Delete'),
              no: tr('Keep'),
              focusYes: false,
              danger: true,
            );
            if (ok) await ref.read(downloadsProvider.notifier).delete(game);
          },
        ),
      if (ref.read(canDeleteGamesProvider).valueOrNull ?? false)
        (
          label: tr('Delete from RomM…'),
          danger: true,
          run: () => deleteGameFromRomm(context, ref, game, downloaded: downloaded),
        ),
    ];
    if (items.isEmpty) return;
    final i = await showDialog<int>(
      context: context,
      builder: (c) => Center(
        child: Material(
          color: GColors.panel,
          borderRadius: BorderRadius.circular(GRadius.lg),
          child: SizedBox(
            width: 320,
            child: Padding(
              padding: const EdgeInsets.all(GSpace.s2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var k = 0; k < items.length; k++) ...[
                    if (items[k].danger && k > 0 && !items[k - 1].danger)
                      const Divider(color: GColors.borderStrong, height: GSpace.s4),
                    GFocusable(
                      autofocus: k == 0,
                      borderRadius: GRadius.md,
                      onActivate: () => Navigator.of(c).pop(k),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: GSpace.s4, vertical: GSpace.s3),
                        child: Text(
                          items[k].label,
                          style: TextStyle(fontSize: GFont.lg, color: items[k].danger ? GColors.danger : GColors.fg),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (i != null) await items[i].run();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(downloadsProvider)[game.id];
    final downloaded = watchDownloaded(ref, game);
    ref.watch(canDeleteGamesProvider); // asked once, ready for ⋯
    final isFavourite = ref.watch(favouriteIdsProvider).contains(game.id);
    final playing = ref.watch(playControllerProvider.select((s) => s.runningGameId == game.id));
    // When this game's session ends, say how its saves went.
    ref.listen(playControllerProvider, (prev, next) {
      if (prev?.runningGameId == game.id && next.runningGameId == null && next.message != null) {
        showToast(context, next.message!);
      }
    });
    final Widget main;
    if (progress?.phase == DownloadPhase.queued) {
      // Waiting for the downloads before it (#143).
      main = Column(
        children: [
          Text(tr('Queued'), style: const TextStyle(color: GColors.fgSecondary)),
          const SizedBox(height: GSpace.s3),
          _wide(tr('Remove from the queue'), Icons.close, () => ref.read(downloadsProvider.notifier).cancel(game.id)),
        ],
      );
    } else if (progress != null && progress.phase != DownloadPhase.failed) {
      final pct = progress.fraction == null ? '' : ' ${(progress.fraction! * 100).round()} %';
      main = Column(
        children: [
          SizedBox(
            width: coverWidth,
            child: LinearProgressIndicator(value: progress.fraction),
          ),
          const SizedBox(height: GSpace.s2),
          Text(
            progress.phase == DownloadPhase.extracting ? tr('Unpacking…') : tr('Downloading{0}', [pct]),
            style: const TextStyle(color: GColors.fgSecondary),
          ),
          // Unpacking can't be stopped halfway, so Cancel goes away once it starts.
          if (progress.phase == DownloadPhase.downloading) ...[
            const SizedBox(height: GSpace.s3),
            _wide(tr('Cancel'), Icons.close, () => ref.read(downloadsProvider.notifier).cancel(game.id)),
          ],
        ],
      );
    } else if (downloaded) {
      main = _wide(
        playing ? tr('Playing…') : tr('Play'),
        Icons.play_arrow,
        playing ? null : () => _play(context),
        primary: true,
      );
    } else {
      final size = game.fileSize > 0 ? ' (${formatBytes(game.fileSize)})' : '';
      final roms = ref.watch(appRootProvider).roms;
      final disk = ref.watch(diskInfoProvider);
      final free = ref.watch(diskUsageProvider).usage(roms)?.free;
      main = Column(
        children: [
          _wide(
            tr('Download{0}', [size]),
            Icons.download,
            () => ref.read(downloadsProvider.notifier).start(game),
            primary: true,
          ),
          // Said before it's pressed when the drive is nearly full (#142).
          if (spaceIsTight(game.fileSize, free) && progress?.phase != DownloadPhase.failed) ...[
            const SizedBox(height: GSpace.s2),
            Text(
              tr('{0} free on {1}', [formatBytes(free!), disk.volumeOf(roms)]),
              key: const ValueKey('free-space'),
              style: const TextStyle(color: GColors.gargosyGold, fontSize: GFont.sm),
            ),
          ],
          if (progress?.phase == DownloadPhase.failed) ...[
            const SizedBox(height: GSpace.s2),
            SizedBox(
              width: coverWidth,
              child: Text(
                tr('The download failed: {0}', [progress!.error]),
                style: const TextStyle(color: GColors.danger, fontSize: GFont.sm),
              ),
            ),
          ],
        ],
      );
    }
    return SizedBox(
      width: coverWidth,
      child: Column(
        children: [
          coverHero(
            game,
            SizedBox(
              key: const ValueKey('game-cover'),
              width: coverWidth,
              height: coverHeight,
              child: CoverImage(
                url: coverUrlFor(ref, game),
                title: game.displayName,
                width: coverWidth,
                height: coverHeight,
              ),
            ),
          ),
          const SizedBox(height: GSpace.s5),
          main,
          const SizedBox(height: GSpace.s3),
          Row(
            children: [
              _small(
                const ValueKey('game-fav'),
                Icon(isFavourite ? Icons.favorite : Icons.favorite_border, color: GColors.fav),
                () => favourite(context, ref, game),
              ),
              const SizedBox(width: GSpace.s2),
              _small(const ValueKey('game-more'), const Icon(Icons.more_horiz), () => _more(context, ref, downloaded)),
            ],
          ),
          const Spacer(),
          OutlinedBackButton(key: const ValueKey('game-back'), label: tr('Back')),
          const SizedBox(height: GSpace.s4),
        ],
      ),
    );
  }
}
