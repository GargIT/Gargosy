import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../library/notifications.dart';
import '../profiles/profile_providers.dart';
import 'engine_providers.dart';
import 'library_providers.dart';
import 'romm_providers.dart';

export '../library/notifications.dart' show Notice;

/// Settings → Display → Notifications (#241); off without preferences.
final notificationsOnProvider = Provider<bool>((ref) {
  final prefs = watchAppPreferencesOrNull(ref);
  return prefs != null && NotificationSettings.on(prefs);
});

/// What waits to be said (#241): `AppShell` says it, one at a time, once
/// no game runs. Nothing is kept while notifications are off.
class NoticeQueue extends StateNotifier<List<Notice>> {
  NoticeQueue(this._on) : super(const []);

  final bool Function() _on;

  void post(Notice notice) {
    if (_on()) state = [...state, notice];
  }

  /// The first waiting, taken off the queue.
  Notice? take() {
    if (state.isEmpty) return null;
    final first = state.first;
    state = state.sublist(1);
    return first;
  }
}

/// Emptied when the profile changes: one profile's news isn't another's.
final noticesProvider = StateNotifierProvider<NoticeQueue, List<Notice>>((ref) {
  ref.watch(activeProfileProvider.select((c) => c?.profile.id));
  return NoticeQueue(() => ref.read(notificationsOnProvider));
});

/// The active profile's watch for other players' shares; null without RomM.
final shareWatchProvider = Provider<ShareWatch?>((ref) {
  final romm = ref.watch(rommServiceProvider);
  final me = ref.watch(rommUserIdProvider);
  if (romm == null || me == null) return null;
  return ShareWatch(
    seen: SharedSeen(ref.watch(profilePrefsProvider)),
    shared: (id) => romm.getSharedOrNull(id, exceptUserId: me),
    post: (n) => ref.read(noticesProvider.notifier).post(n),
  );
});
