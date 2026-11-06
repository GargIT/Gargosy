/// RomM's install requests (#288, RomM 5.4): a game the player sent to this
/// PC from RomM's web page, for Gargosy to download.
class InstallRequest {
  const InstallRequest({required this.id, required this.romId});

  /// RomM's id of the request, which the report names.
  final String id;
  final String romId;

  /// One of RomM's requests as `claim` lists it; null when it isn't one.
  static InstallRequest? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final rom = json['rom_id'];
    if (id is! String || id.isEmpty || rom is! int) return null;
    return InstallRequest(id: id, romId: '$rom');
  }
}

/// What RomM said to a claim.
sealed class InstallClaim {
  const InstallClaim();
}

/// The requests this device holds, oldest first.
class InstallsTaken extends InstallClaim {
  const InstallsTaken(this.requests);
  final List<InstallRequest> requests;
}

/// RomM has no installs: turned off on the server, a RomM before 5.4, or a
/// device it doesn't know.
class InstallsOff extends InstallClaim {
  const InstallsOff();
}

/// The login isn't bound to this device (a password sign-in): only a paired
/// one may claim.
class InstallsNotBound extends InstallClaim {
  const InstallsNotBound();
}

/// How a request ended, as RomM names it.
enum InstallOutcome {
  done('done'),
  alreadyInstalled('already_installed'),
  failed('failed');

  const InstallOutcome(this.name);
  final String name;
}

/// RomM keeps a reason up to this long.
const installReasonMax = 500;
