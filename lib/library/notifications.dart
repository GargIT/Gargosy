import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/app_preferences.dart';
import '../l10n/tr.dart';

/// Settings → Display → Notifications (#241): app-wide, on by default.
class NotificationSettings {
  static const prefKey = 'ui.notifications';

  static bool on(AppPreferences prefs) => prefs.getBool(prefKey) ?? true;
}

/// Something that happened without the player seeing it (#241), said as a
/// toast once no game runs. [gameId]: the game it's about, so a download's
/// news isn't said on that game's own page; [downloads]: how many finished
/// downloads it says.
class Notice {
  const Notice(this.text, {this.gameId, this.downloads = 0});

  final String text;
  final String? gameId;
  final int downloads;

  factory Notice.downloaded(String gameId, String name) =>
      Notice(tr('{0} is downloaded.', [name]), gameId: gameId, downloads: 1);

  /// Several downloads that finished one after another, in one notice.
  factory Notice.downloadsFinished(int n) => Notice(tr('{0} downloads finished.', [n]), downloads: n);

  factory Notice.uploaded(int n) =>
      Notice(n == 1 ? tr('Uploaded 1 save that was waiting.') : tr('Uploaded {0} saves that were waiting.', [n]));

  factory Notice.shared(SharedItem item, String gameName) => Notice(
    item.isState
        ? tr('{0} shared a save state of {1}.', [item.username, gameName])
        : tr('{0} shared a save of {1}.', [item.username, gameName]),
    gameId: item.gameId,
  );
}

/// What waits to be said (#241), in order; the shell says it one at a time
/// once no game runs. Finished downloads waiting next to each other become
/// one notice; at most [cap] wait, the oldest dropped.
class NoticeQueue extends StateNotifier<List<Notice>> {
  NoticeQueue({required this.on}) : super(const []);

  /// Off: nothing is kept.
  final bool on;

  static const cap = 20;

  void post(Notice notice) {
    if (!on || !mounted) return;
    final last = state.lastOrNull;
    if (notice.downloads > 0 && last != null && last.downloads > 0) {
      state = [...state.sublist(0, state.length - 1), Notice.downloadsFinished(last.downloads + notice.downloads)];
      return;
    }
    final next = [...state, notice];
    state = next.length > cap ? next.sublist(next.length - cap) : next;
  }

  /// The first waiting, taken off the queue.
  Notice? take() {
    if (state.isEmpty) return null;
    final first = state.first;
    state = state.sublist(1);
    return first;
  }
}

/// Another player's shared save or state of a game.
class SharedItem {
  const SharedItem({required this.key, required this.gameId, required this.username, required this.isState});

  /// `save:<id>` or `state:<id>`: how it is remembered as seen.
  final String key;
  final String gameId;
  final String username;
  final bool isState;

  /// RomM's `all_user_saves` / `all_user_states` items of a game, others' only.
  static List<SharedItem> of(String gameId, List<Map<String, dynamic>> items, {required bool states}) => [
    for (final item in items)
      if (item['id'] is num)
        SharedItem(
          key: '${states ? 'state' : 'save'}:${(item['id'] as num).toInt()}',
          gameId: gameId,
          username: switch (item['username']?.toString().trim()) {
            final String name when name.isNotEmpty => name,
            _ => tr('Another player'),
          },
          isState: states,
        ),
  ];
}

/// Which other players' shares of which games this profile has seen (#241),
/// in the profile's prefs (`notify.shared`): per game, so one game's many
/// shares never push another's out. A game looked at for the first time has
/// everything it holds taken as seen: only what's shared after that is news,
/// not years of old shares at once.
class SharedSeen {
  SharedSeen(this._prefs);

  static const key = 'notify.shared';

  /// The games remembered, the ones looked at last kept.
  static const keepGames = 500;

  final AppPreferences? _prefs;

  /// One change at a time, across every instance: games are looked at side
  /// by side, and a new watch may start while an old one still writes.
  static Future<void> _last = Future.value();

  Map<String, List<String>> _read() {
    try {
      final j = jsonDecode(_prefs?.getString(key) ?? '{}');
      if (j is Map && j['games'] is Map) {
        return {
          for (final e in (j['games'] as Map).entries)
            '${e.key}': [for (final i in e.value is List ? e.value as List : const []) '$i'],
        };
      }
    } on FormatException {
      // A damaged list starts again.
    }
    return {};
  }

  /// Of [items] (all of [gameId]'s shares RomM has now), those not seen
  /// before; all of them become seen. None the first time the game is looked at.
  Future<List<SharedItem>> news(String gameId, List<SharedItem> items) {
    final done = _last.then((_) => _news(gameId, items));
    _last = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<List<SharedItem>> _news(String gameId, List<SharedItem> items) async {
    final prefs = _prefs;
    if (prefs == null) return const [];
    final games = _read();
    final seen = games[gameId];
    final fresh = [
      for (final i in items)
        if (seen == null || !seen.contains(i.key)) i,
    ];
    if (seen != null && fresh.isEmpty) return const [];
    // This game last, so the oldest looked at go first when there are too many.
    games.remove(gameId);
    games[gameId] = [for (final i in items) i.key];
    final kept = games.entries.skip(games.length > keepGames ? games.length - keepGames : 0);
    await prefs.setString(
      key,
      jsonEncode({
        'games': {for (final e in kept) e.key: e.value},
      }),
    );
    return seen == null ? const [] : fresh;
  }
}

/// Looks for other players' new shares of games on this PC (#241) and says
/// them through [post].
class ShareWatch {
  ShareWatch({required this.seen, required this.shared, required this.post});

  final SharedSeen seen;

  /// RomM's `all_user_saves` and `all_user_states` of a game, others' only;
  /// null when it couldn't be read.
  final Future<({List<Map<String, dynamic>> saves, List<Map<String, dynamic>> states})?> Function(String gameId) shared;
  final void Function(Notice notice) post;

  /// How many games are asked about at once.
  static const atOnce = 4;

  /// [games] (id → name) asked about, [atOnce] at a time; a game RomM can't
  /// say is left for next time.
  Future<void> check(Map<String, String> games) async {
    final ids = games.keys.toList();
    for (var i = 0; i < ids.length; i += atOnce) {
      await Future.wait([for (final id in ids.skip(i).take(atOnce)) _one(id, games[id]!)]);
    }
  }

  Future<void> _one(String gameId, String name) async {
    final both = await shared(gameId);
    if (both == null) return;
    final news = await seen.news(gameId, [
      ...SharedItem.of(gameId, both.saves, states: false),
      ...SharedItem.of(gameId, both.states, states: true),
    ]);
    for (final item in news) {
      post(Notice.shared(item, name));
    }
  }
}

/// The next [count] of [ids] from [cursor], going round: each look at the
/// games on this PC takes the next ones, so every game is looked at in turn.
(List<String>, int) nextRound(List<String> ids, int cursor, int count) {
  if (ids.isEmpty) return (const [], 0);
  final start = cursor % ids.length;
  final picked = [for (var i = 0; i < count && i < ids.length; i++) ids[(start + i) % ids.length]];
  return (picked, (start + picked.length) % ids.length);
}
