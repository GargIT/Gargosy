import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_admin.dart';
import '../../../l10n/tr.dart';
import '../../../library/library_scan.dart';
import '../../../providers/library_providers.dart';
import '../../../providers/romm_providers.dart';
import '../../theme/tokens.dart';
import 'settings_rows.dart';

/// Settings → RomM library (#245): a RomM admin's Scan library, quick or
/// complete, with RomM's progress. Other users read what it needs.
class RommLibrarySection extends ConsumerWidget {
  const RommLibrarySection({super.key});

  /// A refusal shows in the card's line (red), not in a toast as well.
  Future<void> _scan(WidgetRef ref, ScanKind kind) => ref.read(libraryScanProvider.notifier).start(kind);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(rommOfflineProvider);
    final rights = ref.watch(rommRightsProvider).value ?? RommRights.none;
    final scan = ref.watch(libraryScanProvider);
    final line = scanLine(scan);
    final p = scan.progress;
    return ListView(
      children: [
        SettingsCard(
          title: tr('Scan library'),
          icon: Icons.radar,
          note: tr(
            'RomM looks through its folders for games added, changed or removed. Quick looks only at what\'s new; Complete matches every game again, which takes long on a large library.',
          ),
          children: [
            if (offline)
              Text(tr('RomM can\'t be reached.'), style: const TextStyle(color: GColors.fgSecondary))
            else if (!rights.scan)
              Text(
                tr('Your RomM user may not scan the library. An admin can, in RomM or here.'),
                style: const TextStyle(color: GColors.fgSecondary),
              )
            else ...[
              Wrap(
                spacing: GSpace.s2,
                runSpacing: GSpace.s2,
                children: [
                  SettingsButton(
                    key: const Key('scan-quick'),
                    label: tr('Quick scan'),
                    icon: Icons.bolt,
                    kind: SettingsButtonKind.primary,
                    onActivate: scan.running ? null : () => _scan(ref, ScanKind.quick),
                  ),
                  SettingsButton(
                    key: const Key('scan-complete'),
                    label: tr('Complete scan'),
                    icon: Icons.manage_search,
                    onActivate: scan.running ? null : () => _scan(ref, ScanKind.complete),
                  ),
                ],
              ),
              if (line.isNotEmpty) ...[
                const SizedBox(height: GSpace.s3),
                if (scan.running)
                  LinearProgressIndicator(value: p != null && p.totalGames > 0 ? p.scannedGames / p.totalGames : null),
                const SizedBox(height: GSpace.s2),
                Text(
                  line,
                  key: const Key('scan-line'),
                  style: TextStyle(
                    color: scan.error != null || p?.status == 'failed' ? GColors.danger : GColors.fgSecondary,
                  ),
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }
}
