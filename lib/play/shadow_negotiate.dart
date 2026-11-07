import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/emulator/game_launch_service.dart';
import '../core/romm/romm_models.dart';
import '../core/romm/sync_negotiate.dart';
import '../core/save/catalog/play_request.dart';
import '../core/save/catalog/save_entry.dart';
import '../profiles/profile_providers.dart';
import '../providers/romm_providers.dart';

/// How a save on this PC is described to negotiate, from
/// `SaveSyncService.negotiateLocal`.
typedef NegotiateLocal = ({String emulator, String slot, NegotiateSave? save});

/// Asks RomM's negotiate for one game, the seam tests fake.
typedef NegotiateAsk = Future<NegotiateResult?> Function({
  required List<NegotiateSave> saves,
  required List<String> romIds,
  required List<String> emulators,
});

/// Shadow negotiate (#294; why: docs/negotiate-sync.md): before a game's
/// pull and before its push, RomM's negotiate is asked what it would do for
/// that game only (its scope, `restore_unlisted`, the save's emulator), and
/// its answer is logged as `[Negotiate]` lines beside what Gargosy then did.
/// Nothing it says changes anything; it never throws, and the question goes
/// in the background (the save is described only when no save operation
/// runs, `SaveSyncService.negotiateLocal`). RomM's session is always
/// completed, a late answer's too. Once RomM answers it has no negotiate
/// (before 5.4), it isn't asked again this run.
class ShadowNegotiate {
  ShadowNegotiate({required this.ask, required this.complete, this.timeout = const Duration(seconds: 15)});

  final NegotiateAsk ask;
  final Future<void> Function(int sessionId) complete;

  /// How long [ShadowLook.told] waits for the answer to log it.
  final Duration timeout;
  bool _off = false;

  /// Asks now for [game] at [point] (`launch`, `push`); [ShadowLook.told]
  /// logs it beside what Gargosy did. Null when there's nothing to ask.
  ShadowLook? look(String point, Game game, NegotiateLocal? local) {
    if (_off || local == null) return null;
    final answer = ask(saves: [?local.save], romIds: [game.id], emulators: [local.emulator]).then<NegotiateResult?>(
      (r) {
        if (r == null && !_off) {
          _off = true;
          debugPrint('[Negotiate] RomM has no negotiate (older than 5.4): not asked again');
        }
        return r;
      },
      onError: (Object e) {
        debugPrint('[Negotiate] $point ${game.displayName}: RomM could not be asked: $e');
        return null;
      },
    );
    return ShadowLook._(point, game, local, answer, complete, timeout);
  }
}

/// One question to negotiate, waiting for what Gargosy did.
class ShadowLook {
  ShadowLook._(this.point, this.game, this.local, this._answer, this._complete, this._timeout);

  final String point;
  final Game game;
  final NegotiateLocal local;
  final Future<NegotiateResult?> _answer;
  final Future<void> Function(int) _complete;
  final Duration _timeout;
  bool _told = false;

  /// RomM's answer, once it came (for tests).
  Future<NegotiateResult?> get answer => _answer;

  /// Logs RomM's answer beside [gargosyDid], then completes RomM's session.
  /// Only the first call counts (a later one says the launch or push
  /// stopped). An answer later than the timeout isn't logged, but its
  /// session is still completed. Never throws.
  Future<void> told(String gargosyDid) async {
    if (_told) return;
    _told = true;
    final NegotiateResult? r;
    try {
      r = await _answer.timeout(_timeout);
    } on TimeoutException {
      debugPrint('[Negotiate] $point ${game.displayName}: RomM answered too late to compare | Gargosy: $gargosyDid');
      unawaited(_answer.then((late) => late == null ? null : _complete(late.sessionId)));
      return;
    }
    try {
      if (r == null) return;
      final save = local.save;
      final here = save == null
          ? 'no save on this PC'
          : 'this PC: ${save.fileName} ${save.contentHash ?? 'no hash'} ${save.updatedAt.toUtc().toIso8601String()}';
      final ops = r.operations.isEmpty ? 'nothing' : r.operations.join('; ');
      debugPrint(
        '[Negotiate] $point ${game.displayName} (${local.emulator}, ${local.slot}; $here): '
        'RomM would: $ops | Gargosy: $gargosyDid',
      );
      await _complete(r.sessionId);
    } catch (e) {
      debugPrint('[Negotiate] $point ${game.displayName}: not logged: $e');
    }
  }
}

/// What the play screen started with, in words for the log.
String describeChoice(PlayRequest request) {
  final save = request.save;
  if (save == null) return "started with this PC's save";
  return switch (save.source) {
    SaveSource.romm =>
      "started with RomM's save ${save.rommSave?['id'] ?? '?'}${save.owner == null ? '' : ' (another player\'s)'}",
    SaveSource.backup => 'started with a backup',
    SaveSource.local => "started with this PC's save",
  };
}

/// What a pull did, in words for the log.
String describePull(bool? pulled, [Object? error]) => error != null
    ? 'the pull failed ($error)'
    : pulled == true
    ? "pulled RomM's save"
    : "didn't pull (RomM's save is the same, older, or none)";

/// What the push after a session did, in words for the log. A push that
/// uploaded nothing and one that failed look the same from here.
String describePush(LaunchResult? r) {
  if (r == null) return 'no session';
  if (r.saveSyncBlocked != null) return 'not pushed (${r.saveSyncBlocked})';
  if (r.saveConflict != null) return 'conflict (RomM has a newer save)';
  if (r.saveUnchanged) return 'nothing to push (RomM has this save)';
  return r.syncOk ? 'pushed' : 'nothing pushed (no save to upload, or the push failed)';
}

/// The open profile's shadow negotiate: only with a device id and RomM.
final shadowNegotiateProvider = Provider<ShadowNegotiate?>((ref) {
  final romm = ref.watch(rommServiceProvider);
  final deviceId = ref.watch(activeProfileProvider.select((c) => c?.login.deviceId));
  if (romm == null || deviceId == null) return null;
  return ShadowNegotiate(
    ask: ({required saves, required romIds, required emulators}) => romm.negotiateSync(
      deviceId: deviceId,
      saves: saves,
      romIds: romIds,
      restoreUnlisted: true,
      emulators: emulators,
    ),
    complete: romm.completeSync,
  );
});
