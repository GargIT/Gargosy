import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../library/notifications.dart';
import '../profiles/profile_providers.dart';
import 'engine_providers.dart';
import 'library_providers.dart';
import 'romm_providers.dart';

export '../library/notifications.dart' show Notice, NoticeQueue, nextRound;

/// Settings → Display → Notifications (#241); off without preferences.
final notificationsOnProvider = Provider<bool>((ref) {
  final prefs = watchAppPreferencesOrNull(ref);
  return prefs != null && NotificationSettings.on(prefs);
});

/// What waits to be said (#241). A new queue, empty, for another profile and
/// when notifications are turned on or off.
final noticesProvider = StateNotifierProvider<NoticeQueue, List<Notice>>((ref) {
  ref.watch(activeProfileProvider.select((c) => c?.profile.id));
  return NoticeQueue(on: ref.watch(notificationsOnProvider));
});

/// The active profile's watch for other players' shares; null without RomM.
/// It posts to this profile's queue only, even after a switch.
final shareWatchProvider = Provider<ShareWatch?>((ref) {
  final romm = ref.watch(rommServiceProvider);
  final me = ref.watch(rommUserIdProvider);
  if (romm == null || me == null) return null;
  final queue = ref.watch(noticesProvider.notifier);
  return ShareWatch(
    seen: SharedSeen(ref.watch(profilePrefsProvider)),
    shared: (id) => romm.getSharedOrNull(id, exceptUserId: me),
    post: queue.post,
  );
});
