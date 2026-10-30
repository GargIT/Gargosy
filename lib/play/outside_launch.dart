import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profiles/path_guard.dart';
import '../profiles/profile.dart';
import '../providers/update_providers.dart';

/// #223: a game started from outside Gargosy (a shortcut, Steam, Playnite):
/// `Gargosy.exe --play=<rom id> [--profile=<profile id>] [--play-stay]`.
/// The profile opens (its PIN asked), the game's play screen starts at once
/// with what it would preselect, and Gargosy exits once the session's saves
/// are synced, unless [stay].
class OutsideLaunch {
  const OutsideLaunch({required this.romId, this.profileId, this.stay = false});

  static const playArg = '--play=';
  static const profileArg = '--profile=';
  static const stayArg = '--play-stay';

  /// RomM's id of the game.
  final String romId;

  /// The profile to play in; null: the one used last.
  final String? profileId;

  /// Gargosy stays open after the session.
  final bool stay;

  /// The launch [args] ask for, or null. A rom id that isn't RomM's (digits)
  /// or a profile id that isn't one is no launch: Gargosy starts as usual.
  static OutsideLaunch? parse(List<String> args) {
    String? valueOf(String prefix) {
      for (final a in args) {
        if (a.startsWith(prefix)) return a.substring(prefix.length);
      }
      return null;
    }

    final rom = valueOf(playArg);
    if (rom == null || !_romId.hasMatch(rom)) return null;
    final profile = valueOf(profileArg);
    if (profile != null && !PathGuard.isProfileId(profile)) return null;
    return OutsideLaunch(romId: rom, profileId: profile, stay: args.contains(stayArg));
  }

  static final _romId = RegExp(r'^[0-9]{1,18}$');

  /// The profile to open among [profiles]: the one named, else [lastUsedId]'s,
  /// else the only one. Null when it isn't there.
  Profile? profileIn(List<Profile> profiles, String? lastUsedId) {
    Profile? byId(String? id) {
      for (final p in profiles) {
        if (p.id == id) return p;
      }
      return null;
    }

    if (profileId != null) return byId(profileId);
    return byId(lastUsedId) ?? (profiles.length == 1 ? profiles.single : null);
  }
}

/// The launch still to run: set from the arguments at start, taken (set to
/// null) by the profile picker when it can't open the profile, and by the
/// shell when it starts the game.
final outsideLaunchProvider = StateProvider<OutsideLaunch?>((ref) => OutsideLaunch.parse(ref.read(launchArgsProvider)));
