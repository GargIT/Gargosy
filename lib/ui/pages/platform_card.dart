import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_models.dart';
import '../../library/platform_covers.dart';
import '../../library/platform_facts.dart';
import '../../providers/library_providers.dart';
import '../theme/tokens.dart';
import '../widgets/cover_image.dart';
import '../widgets/g_focusable.dart';
import '../widgets/platform_logo.dart';

/// A platform on the Platforms page: a fan of up to five covers (the Covers
/// setting), then its logo, name and "maker · year · N games".
class PlatformCard extends ConsumerWidget {
  const PlatformCard({super.key, required this.platform, required this.onOpen, this.autofocus = false});

  final Platform platform;
  final VoidCallback onOpen;
  final bool autofocus;

  static const height = 190.0;
  static const _stripHeight = 120.0;

  /// The five places in the fan, left to right: tilt in degrees and drop.
  static const _fan = [(-10.0, 8.0), (-4.0, 0.0), (0.0, -6.0), (4.0, 0.0), (10.0, 8.0)];

  /// Places for [n] covers, filled from the middle out, left to right.
  static List<int> _places(int n) => ([2, 1, 3, 0, 4].take(n).toList()..sort());

  Widget _strip(WidgetRef ref, List<Game> covers) {
    if (covers.isEmpty) {
      return Center(
        child: PlatformLogo(key: const ValueKey('platform-strip-logo'), slug: platform.slug, size: 80),
      );
    }
    final places = _places(covers.length);
    // Two or four covers fill places off the middle; shift them back to centre.
    final shift = (places.first + places.last) / 2 - 2;
    // The middle is painted last, so it sits on top.
    final paintOrder = [for (var i = 0; i < places.length; i++) i]
      ..sort((a, b) => (places[b] - 2).abs().compareTo((places[a] - 2).abs()));
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        for (final i in paintOrder)
          Transform.translate(
            offset: Offset((places[i] - 2 - shift) * 44.0, _fan[places[i]].$2),
            child: Transform.rotate(
              angle: _fan[places[i]].$1 * math.pi / 180,
              child: Container(
                key: const ValueKey('strip-cover'),
                width: 66,
                height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(GRadius.sm),
                  boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(0, 5))],
                ),
                child: CoverImage(
                  url: coverUrlFor(ref, covers[i], small: true),
                  title: covers[i].displayName,
                  radius: GRadius.sm,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(platformCoversChoiceProvider);
    final covers = ref.watch(platformCoversProvider(PlatformCoversKey(platform, choice))).valueOrNull ?? const <Game>[];
    return GFocusable(
      key: ValueKey('platform-card-${platform.id}'),
      autofocus: autofocus,
      onActivate: onOpen,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: GColors.surface, borderRadius: BorderRadius.circular(GRadius.card)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const ValueKey('platform-strip'),
              height: _stripHeight,
              padding: const EdgeInsets.only(bottom: GSpace.s2),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x08FFFFFF), Color(0x40000000)],
                ),
              ),
              child: _strip(ref, covers),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: GSpace.s3),
                child: Row(
                  children: [
                    PlatformLogo(slug: platform.slug),
                    const SizedBox(width: GSpace.s3),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            platform.nameForDisplay,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: GFont.lg, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            platformLine(platform),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: GFont.sm, color: GColors.fgMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
