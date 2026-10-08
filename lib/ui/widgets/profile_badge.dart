import 'dart:io' as io;

import 'package:flutter/material.dart';

import '../../profiles/profile.dart';
import '../theme/tokens.dart';
import 'g_focusable.dart';

/// A round Plex-style badge: the RomM avatar or the initial on the profile's
/// colour, a lock when there is a PIN, and the name (spec §5).
class ProfileBadge extends StatelessWidget {
  const ProfileBadge({
    super.key,
    required this.profile,
    this.avatarPath,
    this.size = 120,
    this.showName = true,
    this.onActivate,
    this.onDetail,
    this.autofocus = false,
    this.focusNode,
  });

  final Profile profile;
  final String? avatarPath;
  final double size;
  final bool showName;
  final VoidCallback? onActivate;
  final VoidCallback? onDetail;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final color = GColors.profileColors[profile.colorIndex % GColors.profileColors.length];
    final avatar = avatarPath != null && profile.hasAvatar && io.File(avatarPath!).existsSync() ? io.File(avatarPath!) : null;
    final circle = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      alignment: Alignment.center,
      child: avatar != null
          // From memory, not Image.file: the file is replaced when RomM's avatar
          // changes, and Image.file would keep showing the cached old one.
          ? Image.memory(avatar.readAsBytesSync(), width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true)
          : Text(profile.name.isEmpty ? '?' : profile.name.characters.first.toUpperCase(),
              style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: GColors.bg)),
    );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GFocusable(
        autofocus: autofocus,
        focusNode: focusNode,
        borderRadius: GRadius.pill,
        onActivate: onActivate,
        onDetail: onDetail,
        semanticLabel: profile.name,
        child: Stack(clipBehavior: Clip.none, children: [
          circle,
          if (profile.pin != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: GColors.panel, shape: BoxShape.circle),
                child: Icon(Icons.lock, size: size * 0.16, color: GColors.fgSecondary),
              ),
            ),
        ]),
      ),
      if (showName) ...[
        const SizedBox(height: GSpace.s3),
        // The name is clickable too, like the badge.
        GestureDetector(
          onTap: onActivate,
          child: Text(profile.name, style: const TextStyle(fontSize: GFont.xl, fontWeight: FontWeight.w600)),
        ),
      ],
    ]);
  }
}
