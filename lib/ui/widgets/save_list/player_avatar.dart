import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/save/catalog/save_entry.dart';
import '../../../providers/library_providers.dart';
import '../../theme/tokens.dart';

/// Another RomM player's mark beside their shared saves (#92): their avatar
/// on RomM when they have one (#180), else their first letter on a colour of
/// their own.
class PlayerAvatar extends ConsumerWidget {
  const PlayerAvatar(this.owner, {super.key, this.size = 26});

  final SaveOwner owner;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = owner.username.trim();
    const colors = GColors.profileColors;
    final picture = owner.avatarPath == null ? null : ref.watch(userAvatarProvider(owner.userId)).value;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: colors[owner.userId.abs() % colors.length], shape: BoxShape.circle),
      child: picture != null
          ? Image.memory(picture, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true)
          : Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(fontSize: size * 0.46, fontWeight: FontWeight.w800, color: GColors.bg),
            ),
    );
  }
}
