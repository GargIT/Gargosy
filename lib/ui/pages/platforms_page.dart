import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_library_api.dart';
import '../../core/romm/romm_models.dart';
import '../../providers/library_providers.dart';
import '../input/wrap_grid_policy.dart';
import '../screens/gallery_screen.dart';
import '../theme/tokens.dart';
import '../widgets/error_retry.dart';
import '../widgets/g_focusable.dart';

/// All platforms with games; A opens a platform's gallery.
class PlatformsPage extends ConsumerWidget {
  const PlatformsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platforms = ref.watch(platformsProvider);
    return Padding(
      key: const Key('page-Platforms'),
      padding: const EdgeInsets.only(top: GLayout.navHeight + GSpace.s6),
      child: platforms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(message: describeLoadError(e), onRetry: () => ref.invalidate(platformsProvider)),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No platforms with games yet.', style: TextStyle(color: GColors.fgMuted)))
            : FocusTraversalGroup(
                policy: WrapGridTraversalPolicy(),
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(GSpace.rowPad, 0, GSpace.rowPad, GSpace.s14),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisExtent: 120,
                    mainAxisSpacing: GSpace.s4,
                    crossAxisSpacing: GSpace.s4,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _PlatformTile(platform: list[i], autofocus: i == 0),
                ),
              ),
      ),
    );
  }
}

class _PlatformTile extends StatelessWidget {
  const _PlatformTile({required this.platform, this.autofocus = false});

  final Platform platform;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return GFocusable(
      autofocus: autofocus,
      onActivate: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GalleryScreen(title: platform.nameForDisplay, query: GalleryQuery(platformId: platform.id)),
      )),
      child: Container(
        padding: const EdgeInsets.all(GSpace.s4),
        decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.card)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
          Text(platform.nameForDisplay,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w700)),
          Text('${platform.gamesCount} games', style: const TextStyle(color: GColors.fgMuted)),
        ]),
      ),
    );
  }
}
