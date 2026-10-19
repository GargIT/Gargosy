import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/g_focusable.dart';

enum ProfileOption { delete }

/// X on a badge: what you can do with a profile. Milestone A: delete.
Future<ProfileOption?> showProfileOptions(BuildContext context, {required String name}) => showDialog<ProfileOption>(
  context: context,
  builder: (c) => AlertDialog(
    title: Text(name),
    content: GFocusable(
      autofocus: true,
      borderRadius: GRadius.md,
      onActivate: () => Navigator.of(c).pop(ProfileOption.delete),
      child: const Padding(
        padding: EdgeInsets.all(GSpace.s3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: GColors.danger),
            SizedBox(width: GSpace.s3),
            Text('Delete profile', style: TextStyle(fontSize: GFont.lg)),
          ],
        ),
      ),
    ),
  ),
);

/// The last question before deleting. Says that nothing on RomM is touched.
Future<bool> confirmDeleteProfile(BuildContext context, {required String name}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Delete $name?'),
      content: const Text(
        'This removes the profile and its saves, states and emulator settings from this PC. '
        'Nothing on the RomM server is deleted.',
      ),
      actions: [
        GFocusable(
          autofocus: true,
          borderRadius: GRadius.pill,
          onActivate: () => Navigator.of(c).pop(false),
          child: const Padding(padding: EdgeInsets.all(GSpace.s3), child: Text('Keep')),
        ),
        GFocusable(
          borderRadius: GRadius.pill,
          onActivate: () => Navigator.of(c).pop(true),
          child: const Padding(
            padding: EdgeInsets.all(GSpace.s3),
            child: Text('Delete', style: TextStyle(color: GColors.danger)),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}
