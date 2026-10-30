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

  /// The profile to play in; null: the only one, else the one picked.
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

  /// The profile to open among [profiles] without asking: the one named,
  /// else the only one. Null when it isn't there, or when the player must
  /// say who is playing (several profiles, none named: a shortcut shared by
  /// a family never plays as whoever was last).
  Profile? profileIn(List<Profile> profiles) =>
      profileId == null ? profiles.singleOrNull : profiles.where((p) => p.id == profileId).firstOrNull;
}

/// The launch still to run: set from the arguments at start, taken (set to
/// null) by the profile picker when it can't open the profile, and by the
/// shell when it starts the game.
final outsideLaunchProvider = StateProvider<OutsideLaunch?>((ref) => OutsideLaunch.parse(ref.read(launchArgsProvider)));

/// The arguments of each later start of Gargosy, handed over to this one
/// (`AppInstance.requests`, from `main.dart`); none in tests.
final instanceRequestsProvider = Provider<Stream<List<String>>>((ref) => const Stream.empty());
