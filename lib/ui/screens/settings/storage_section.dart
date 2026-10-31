import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../library/download_check.dart';
import 'download_limit_fields.dart';
import '../../../library/storage_usage.dart';
import '../../../play/play_controller.dart';
import '../../../profiles/path_guard.dart';
import '../../../profiles/profile_providers.dart';
import '../../../providers/download_providers.dart';
import '../../../providers/engine_providers.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/format.dart';
import '../../widgets/toast.dart';
import '../storage_platform_screen.dart';
import 'image_cache_section.dart';
import 'settings_rows.dart';
import '../../../l10n/tr.dart';

/// What Gargosy's folders take, read again when Storage opens (#145).
final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>((ref) => readStorage(ref.watch(appRootProvider)));

/// A platform's name from its folder (RomM's slug).
String platformNameFor(WidgetRef ref, String folder) {
  final platforms = ref.watch(platformsProvider).value ?? const [];
  return platforms.where((x) => x.slug == folder).firstOrNull?.name ?? folder;
}

/// Settings → Storage (#145): the drive, what Gargosy's folders take, the
/// ROMs by platform (A opens one: its games, to delete from this PC), Temp
/// emptied, and the image cache.
class StorageSection extends ConsumerStatefulWidget {
  const StorageSection({super.key});

  @override
  ConsumerState<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<StorageSection> {
  bool _emptying = false;

  /// Temp's leftovers: never while a download, a game or a sync might use them.
  Future<void> _emptyTemp() async {
    if (ref.read(downloadsProvider.notifier).pending > 0 ||
        ref.read(playControllerProvider).runningGameId != null ||
        ref.read(syncActivityProvider)?.value != null) {
      showToast(context, tr('Not while a download, a game or a save sync runs.'));
      return;
    }
    setState(() => _emptying = true);
    final root = ref.read(appRootProvider);
    final guard = PathGuard(root);
    final temp = p.join(root.appData, 'temp');
    try {
      if (io.Directory(temp).existsSync()) {
        for (final e in io.Directory(temp).listSync(followLinks: false)) {
          try {
            e is io.Directory ? e.deleteSync(recursive: true) : io.File(guard.check(e.path)).deleteSync();
          } on io.FileSystemException {
            // In use: left for next time.
          }
        }
      }
    } finally {
      ref.invalidate(storageUsageProvider);
      ref.invalidate(diskUsageProvider);
      if (mounted) setState(() => _emptying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final root = ref.watch(appRootProvider);
    final volumes = ref.watch(diskInfoProvider);
    final disk = ref.watch(diskUsageProvider).usage(root.root);
    final usage = ref.watch(storageUsageProvider);
    final counting = switch (usage) {
      AsyncError() => tr('Couldn\'t be read'),
      _ => tr('Counting…'),
    };
    final folders = usage.value?.folders;
    final platforms = usage.value?.platforms ?? const <PlatformUsage>[];
    return ListView(
      children: [
        SettingsCard(
          title: tr('Storage'),
          icon: Icons.storage,
          note: tr(
            'What takes space in the Gargosy folder on this PC. ROMs are shared by every profile; saves aren\'t in them.',
          ),
          children: [
            if (disk != null) ...[
              SettingsField(
                key: const ValueKey('storage-drive'),
                label: tr('Drive {0}', [volumes.volumeOf(root.root)]),
                value: tr('{0} free of {1}', [formatBytes(disk.free), formatBytes(disk.total)]),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(GRadius.pill),
                child: LinearProgressIndicator(value: disk.total == 0 ? 0 : 1 - disk.free / disk.total),
              ),
            ],
            for (final label in folders?.keys ?? const ['ROMs'])
              SettingsField(label: tr(label), value: folders == null ? counting : formatBytes(folders[label]!)),
            Align(
              alignment: Alignment.centerLeft,
              child: SettingsButton(
                key: const ValueKey('storage-empty-temp'),
                label: _emptying ? tr('Emptying…') : tr('Empty Temp'),
                icon: Icons.delete_sweep_outlined,
                onActivate: _emptying ? null : _emptyTemp,
              ),
            ),
          ],
        ),
        SettingsCard(
          title: tr('ROMs by platform'),
          icon: Icons.sports_esports_outlined,
          note: tr('Largest first. Open one to see its games and delete them from this PC.'),
          children: [
            if (usage.isLoading) Text(tr('Counting…'), style: const TextStyle(color: GColors.fgMuted)),
            if (!usage.isLoading && platforms.isEmpty)
              Text(tr('No ROMs on this PC yet.'), style: const TextStyle(color: GColors.fgMuted)),
            for (final (i, x) in platforms.indexed)
              SettingsField(
                key: ValueKey('storage-platform-${x.folder}'),
                autofocus: i == 0,
                label: platformNameFor(ref, x.folder),
                value: '${formatBytes(x.bytes)} · ${x.entries.length} ${x.entries.length == 1 ? 'game' : 'games'}',
                action: tr('Open'),
                onActivate: () async {
                  await Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => StoragePlatformScreen(folder: x.folder)));
                  ref.invalidate(storageUsageProvider);
                },
              ),
          ],
        ),
        SettingsCard(
          title: tr('Downloads'),
          icon: Icons.download,
          children: [
            SettingsToggle(
              label: tr('Check downloads'),
              note: tr(
                'Each download is checked against RomM\'s hashes before it goes into roms\\, so a damaged one is never played. Off, downloads go in unchecked: quicker with large discs on a slow PC.',
              ),
              on: DownloadCheck.of(ref.watch(appPreferencesProvider)),
              onChanged: (on) async {
                await ref.read(appPreferencesProvider).setBool(DownloadCheck.key, on);
                if (mounted) setState(() {});
              },
            ),
            ...downloadLimitFields(context, ref, () {
              if (mounted) setState(() {});
            }),
          ],
        ),
        const ImageCacheCard(),
      ],
    );
  }
}
