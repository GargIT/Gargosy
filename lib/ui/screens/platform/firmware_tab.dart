import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/romm/romm_models.dart';
import '../../../emulators/bios_links.dart';
import '../../../emulators/bios_sync.dart';
import '../../../library/platform_firmware.dart';
import '../../../play/play_controller.dart';
import '../../../profiles/profile_providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/format.dart';
import '../../widgets/g_focusable.dart';
import '../../widgets/toast.dart';

/// The platform page's Firmware / BIOS tab: RomM's files for the platform,
/// each on this PC (in the shared `bios\`) or missing, and one button that
/// gets the missing ones from RomM (`BiosSync`). Refused while a game runs.
class FirmwareTab extends ConsumerStatefulWidget {
  const FirmwareTab({super.key, required this.platform});

  final Platform platform;

  @override
  ConsumerState<FirmwareTab> createState() => _FirmwareTabState();
}

class _FirmwareTabState extends ConsumerState<FirmwareTab> {
  bool _busy = false;

  Future<void> _getMissing() async {
    if (_busy) return;
    if (ref.read(playControllerProvider).runningGameId != null) {
      showToast(context, 'A game is running. Close it first.');
      return;
    }
    final sync = ref.read(biosSyncProvider);
    if (sync == null) {
      showToast(context, "Can't reach RomM.");
      return;
    }
    setState(() => _busy = true);
    try {
      final n = await sync.forPlatform(widget.platform.slug);
      if (mounted) showToast(context, n == 0 ? 'Nothing new came from RomM.' : 'Got $n from RomM.');
    } on Object catch (e) {
      if (mounted) showToast(context, "Couldn't get the files: $e");
    } finally {
      // The rebuild reads bios\ again.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.platform;
    if (p.firmware.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(GSpace.rowPad),
        child: Text('RomM has no firmware for this platform.', style: TextStyle(color: GColors.fgSecondary)),
      );
    }
    final bios = ref.watch(appRootProvider).bios;
    final files = firmwareOnThisPc(p.firmware, BiosFiles(bios), platformSlug: p.slug);
    final have = files.where((f) => f.onThisPc).length;
    final missing = files.length - have;
    const head = TextStyle(fontSize: GFont.xs, fontWeight: FontWeight.w700, letterSpacing: 1, color: GColors.fgMuted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, GSpace.s4, GSpace.rowPad, GSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$have of ${files.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: GColors.fg),
                      ),
                      const TextSpan(text: ' on this PC, in '),
                      const TextSpan(
                        text: r'bios\',
                        style: TextStyle(fontFamily: 'Consolas'),
                      ),
                      TextSpan(text: missing == 0 ? '.' : '. $missing missing.'),
                    ],
                  ),
                  style: const TextStyle(fontSize: GFont.lg, color: GColors.fgSecondary),
                ),
              ),
              GFocusable(
                key: const ValueKey('firmware-get'),
                borderRadius: GRadius.pill,
                onActivate: missing == 0 ? null : _getMissing,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
                  decoration: BoxDecoration(
                    color: missing == 0 ? GColors.surface : GColors.primary,
                    borderRadius: BorderRadius.circular(GRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(missing == 0 ? Icons.check : Icons.download, size: 18),
                      const SizedBox(width: GSpace.s2),
                      Text(
                        _busy
                            ? 'Getting…'
                            : missing == 0
                            ? 'All on this PC'
                            : 'Get missing from RomM',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: GSpace.s4),
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                color: GColors.card,
                borderRadius: BorderRadius.circular(GRadius.card),
                border: Border.all(color: GColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
                    child: Row(
                      children: [
                        Expanded(child: Text('FILE', style: head)),
                        SizedBox(width: 120, child: Text('SIZE', style: head)),
                        SizedBox(width: 160, child: Text('THIS PC', style: head)),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: GColors.border),
                  Flexible(child: ListView(shrinkWrap: true, children: [for (final f in files) _FirmwareRow(f)])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirmwareRow extends StatelessWidget {
  const _FirmwareRow(this.status);
  final FirmwareStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.onThisPc ? GColors.success : GColors.accent;
    // Focusable so a controller can scroll a long list.
    return GFocusable(
      borderRadius: GRadius.md,
      semanticLabel: status.firmware.fileName,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GSpace.s5, vertical: GSpace.s3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                status.firmware.fileName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: GFont.md),
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                formatBytes(status.firmware.fileSizeBytes),
                style: const TextStyle(fontSize: GFont.md, color: GColors.fgSecondary),
              ),
            ),
            SizedBox(
              width: 160,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: GSpace.s2),
                  Flexible(
                    child: Text(
                      status.onThisPc ? 'On this PC' : 'Missing',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: GFont.md, fontWeight: FontWeight.w600, color: color),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
