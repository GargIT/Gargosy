import 'package:flutter/material.dart';

import '../../../core/save/catalog/save_entry.dart';
import '../../theme/tokens.dart';

/// Another RomM player's mark beside their shared saves (#92): their first
/// letter on a colour of their own.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar(this.owner, {super.key, this.size = 26});

  final SaveOwner owner;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = owner.username.trim();
    const colors = GColors.profileColors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors[owner.userId.abs() % colors.length], shape: BoxShape.circle),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.46, fontWeight: FontWeight.w800, color: GColors.bg),
      ),
    );
  }
}
