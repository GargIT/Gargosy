import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/image_cache.dart';
import '../../widgets/controller_dialogs.dart';
import '../../widgets/format.dart';
import '../../widgets/romm_images.dart';
import 'settings_rows.dart';
import '../../../l10n/tr.dart';

/// 25000 → "25 000".
String _grouped(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ' ');

String imageCacheChoiceLabel(int n) =>
    tr('{0} images (about {1})', [_grouped(n), formatBytes(n * ImageCacheSize.bytesPerImage)]);

/// Settings → Storage's Image cache card: how many covers and logos this PC
/// keeps, what they take now, and Clear.
class ImageCacheCard extends ConsumerStatefulWidget {
  const ImageCacheCard({super.key, this.autofocus = false});

  final bool autofocus;

  @override
  ConsumerState<ImageCacheCard> createState() => _ImageCacheCardState();
}

class _ImageCacheCardState extends ConsumerState<ImageCacheCard> {
  bool _clearing = false;

  Future<void> _pick(int current) async {
    const choices = ImageCacheSize.choices;
    final i = await showChoice(
      context,
      title: tr('Keep up to'),
      labels: [for (final n in choices) imageCacheChoiceLabel(n)],
      current: choices.indexOf(current),
    );
    if (i == null || i < 0) return;
    await ref.read(imageCacheSizeProvider.notifier).pick(choices[i]);
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    try {
      await ref.read(rommImageCacheProvider).emptyCache();
    } finally {
      ref.invalidate(imageCacheUsageProvider);
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = ref.watch(imageCacheSizeProvider);
    final usage = ref.watch(imageCacheUsageProvider);
    return SettingsCard(
      title: tr('Image cache'),
      icon: Icons.photo_library_outlined,
      note: tr(
        'Covers and platform logos kept on this PC, so browsing doesn\'t ask RomM for them again. Grids use RomM\'s small covers, a game\'s page the large one. Past the limit, the ones looked at longest ago go. This PC\'s setting, for every profile.',
      ),
      children: [
        SettingsField(
          key: const ValueKey('image-cache-size'),
          label: tr('Keep up to'),
          value: imageCacheChoiceLabel(size),
          action: tr('Change'),
          onActivate: () => _pick(size),
          autofocus: widget.autofocus,
        ),
        SettingsField(
          key: const ValueKey('image-cache-usage'),
          label: tr('On this PC now'),
          value: switch (usage) {
            AsyncData(:final value) => tr('{0} images · {1}', [_grouped(value.files), formatBytes(value.bytes)]),
            AsyncError() => tr('Couldn\'t be read'),
            _ => tr('Counting…'),
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SettingsButton(
            key: const ValueKey('image-cache-clear'),
            label: _clearing ? tr('Clearing…') : tr('Clear the cache'),
            icon: Icons.delete_sweep_outlined,
            onActivate: _clearing ? null : _clear,
          ),
        ),
      ],
    );
  }
}
