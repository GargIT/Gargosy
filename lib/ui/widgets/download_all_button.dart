import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_library_api.dart';
import '../../core/romm/romm_models.dart';
import '../../library/disk_space.dart';
import '../../library/download_all.dart';
import '../../library/library_snapshot.dart';
import '../../profiles/profile_providers.dart';
import '../../providers/download_providers.dart';
import '../../providers/romm_providers.dart';
import '../theme/tokens.dart';
import 'controller_dialogs.dart';
import 'format.dart';
import 'g_focusable.dart';
import 'toast.dart';
import '../../l10n/tr.dart';

/// #226: Download all, on a collection's and a platform's header: every game
/// of [query] not on this PC or queued already, its size checked against the
/// free space of `roms\`'s drive, then queued in the gallery's order after a
/// confirm.
class DownloadAllButton extends ConsumerStatefulWidget {
  const DownloadAllButton({super.key, required this.query});

  final GalleryQuery query;

  @override
  ConsumerState<DownloadAllButton> createState() => _DownloadAllButtonState();
}

class _DownloadAllButtonState extends ConsumerState<DownloadAllButton> {
  bool _reading = false;

  Future<void> _run() async {
    final api = ref.read(libraryApiProvider);
    if (api == null || _reading) return;
    final files = ref.read(romFilesProvider);
    final downloads = ref.read(downloadsProvider);
    // On this PC from any profile (roms\ is shared), or waiting already.
    final have = {
      for (final g in ref.read(gamesOnThisPcProvider)) g.id,
      for (final MapEntry(:key, :value) in downloads.entries)
        if (value.phase.active) key,
    };
    setState(() => _reading = true);
    final List<Game> games;
    try {
      final found = await gamesToDownload(
        api,
        widget.query,
        skip: (g) => have.contains(g.id) || files.isDownloaded(g),
        have: have,
      );
      games = ref.read(ageLimitProvider).only(found);
    } on Object catch (e) {
      debugPrint('[Downloads] Download all: $e');
      if (mounted) showToast(context, tr('RomM\'s games couldn\'t be read.'));
      return;
    } finally {
      if (mounted) setState(() => _reading = false);
    }
    if (!mounted) return;
    if (games.isEmpty) {
      showToast(context, tr('Nothing here to download: every game is on this PC or waiting.'));
      return;
    }
    final size = sizeOf(games);
    final notifier = ref.read(downloadsProvider.notifier);
    try {
      // With what is queued or running already, as each download is checked.
      checkSpace({ref.read(appRootProvider).roms: size + notifier.stillToCome()}, ref.read(diskInfoProvider));
    } on NotEnoughSpace catch (e) {
      showToast(context, '$e');
      return;
    }
    final ok = await showConfirm(
      context,
      title: games.length == 1 ? tr('Download 1 game?') : tr('Download {0} games?', [games.length]),
      body: tr('About {0} in all. They wait in Downloads, one at a time.', [formatBytes(size)]),
      yes: tr('Download all'),
    );
    if (!ok || !mounted) return;
    try {
      notifier.startAll(games);
    } on NotEnoughSpace catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to ask without RomM.
    if (ref.watch(libraryApiProvider) == null) return const SizedBox.shrink();
    return _button();
  }

  Widget _button() => GFocusable(
    key: const ValueKey('download-all'),
    borderRadius: GRadius.pill,
    onActivate: _run,
    semanticLabel: 'Download all',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
      decoration: BoxDecoration(
        color: GColors.surface,
        borderRadius: BorderRadius.circular(GRadius.pill),
        border: Border.all(color: GColors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _reading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download, size: 18),
          const SizedBox(width: GSpace.s2),
          Text(tr('Download all'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}
