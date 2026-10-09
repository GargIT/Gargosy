import 'dart:async';

import '../core/save/save_strategy.dart';

/// Freegosy's pre-launch pull: back up this PC's save, then pull the
/// profile's RomM save. It never stops the launch: a failure is told
/// ([onProblem]) or only logged, and the game starts with the save on this
/// PC. A pull that put a save in place is [markSynced] (it is what RomM has,
/// so an unchanged save isn't uploaded again at exit).
///
/// When [mustFinish] (a save file other games share, e.g. a memory card),
/// the launch waits up to [wait] for the pull; a pull still running then is
/// marked too late through [SaveRestoreGuard] and writes nothing, so it
/// can't change a file the emulator already has open. Otherwise the pull
/// runs alongside the launch.
Future<void> pullBeforeLaunch({
  required Future<void> Function() backUp,
  required Future<bool> Function() pull,
  required Future<void> Function() markSynced,
  required Future<bool> Function() mustFinish,
  Duration wait = const Duration(seconds: 20),
  void Function(String reason)? onProblem,
}) async {
  final guard = SaveRestoreGuard();
  final pulled = guard.run(() => backUp().then((_) => pull())).catchError((Object e) {
    // How the emulator is set up (no card, …) holds for every launch: the
    // session's result says it; a problem with this one save is told now.
    if (e is SaveSyncNotPossibleException && e is! SaveSyncBlockedException) onProblem?.call(e.message);
    return false;
  });
  unawaited(pulled.then((ok) => ok ? markSynced() : null).catchError((Object _) {}));
  bool waitForIt;
  try {
    waitForIt = await mustFinish();
  } on Object {
    waitForIt = false;
  }
  if (!waitForIt) return;
  await pulled.timeout(wait, onTimeout: () {
    guard.markTooLate();
    onProblem?.call("The save from RomM didn't arrive in time, so the game starts with the save on this PC.");
    return false;
  });
}
