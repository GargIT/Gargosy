import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_models.dart';
import '../../library/platform_covers.dart';
import '../../providers/library_providers.dart';
import '../input/wrap_grid_policy.dart';
import '../screens/platform/platform_screen.dart';
import '../theme/tokens.dart';
import '../widgets/error_retry.dart';
import '../widgets/g_dropdown.dart';
import 'platform_card.dart';
import '../../l10n/tr.dart';

/// All platforms with games, as cover-strip cards: as many per row as fit;
/// the Covers setting picks what each card fans. A opens a platform's gallery.
class PlatformsPage extends ConsumerStatefulWidget {
  const PlatformsPage({super.key});

  @override
  ConsumerState<PlatformsPage> createState() => _PlatformsPageState();
}

class _PlatformsPageState extends ConsumerState<PlatformsPage> {
  final _coversField = GlobalKey();
  bool _coversOpen = false;

  Future<void> _pickCovers() async {
    final current = ref.read(platformCoversChoiceProvider);
    setState(() => _coversOpen = true);
    final i = await showDropdown(
      context,
      field: _coversField,
      labels: [for (final c in PlatformCovers.values) c.label],
      current: current.index,
    );
    if (!mounted) return;
    setState(() => _coversOpen = false);
    if (i != null) await ref.read(platformCoversChoiceProvider.notifier).pick(PlatformCovers.values[i]);
  }

  Widget _heading(List<Platform> list) {
    final games = list.fold<int>(0, (n, p) => n + p.gamesCount);
    final choice = ref.watch(platformCoversChoiceProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(GSpace.rowPad, 0, GSpace.rowPad, GSpace.s5),
      child: Row(
        children: [
          Text(
            tr('Platforms'),
            style: const TextStyle(fontSize: GFont.xxl, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: GSpace.s3),
          Expanded(
            child: Text(
              tr('{0} platforms · {1} games', [list.length, games]),
              key: const ValueKey('platforms-heading'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: GColors.fgMuted),
            ),
          ),
          KeyedSubtree(
            key: _coversField,
            child: GDropdownField(
              key: const ValueKey('platforms-covers'),
              icon: Icons.photo_library_outlined,
              text: tr('Covers: {0}', [choice.label]),
              onPress: _pickCovers,
              open: _coversOpen,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  void _openGallery(BuildContext context, Platform p) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlatformScreen(platform: p)));

  @override
  Widget build(BuildContext context) {
    final platforms = ref.watch(platformsProvider);
    return Padding(
      key: const Key('page-Platforms'),
      padding: const EdgeInsets.only(top: GLayout.navHeight + GSpace.s6),
      child: platforms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(message: describeLoadError(e), onRetry: () => ref.invalidate(platformsProvider)),
        data: (list) => list.isEmpty
            ? Center(
                child: Text(tr('No platforms with games yet.'), style: const TextStyle(color: GColors.fgMuted)),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _heading(list),
                  Expanded(
                    child: FocusTraversalGroup(
                      policy: WrapGridTraversalPolicy(),
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(GSpace.rowPad, 0, GSpace.rowPad, GSpace.s14),
                        // About 260–300 px a card: 6 / 4 / 3 per row at 1920 / 1280 / 900 px.
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 300,
                          mainAxisExtent: PlatformCard.height,
                          mainAxisSpacing: GSpace.s4,
                          crossAxisSpacing: GSpace.s4,
                        ),
                        itemCount: list.length,
                        itemBuilder: (context, i) => PlatformCard(
                          platform: list[i],
                          autofocus: i == 0,
                          onOpen: () => _openGallery(context, list[i]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
