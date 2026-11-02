import 'dart:convert';

import '../core/storage/app_preferences.dart';
import '../l10n/tr.dart';

/// Settings → Display → Notifications (#241): app-wide, on by default.
class NotificationSettings {
  static const prefKey = 'ui.notifications';

  static bool on(AppPreferences prefs) => prefs.getBool(prefKey) ?? true;
}

/// Something that happened without the player seeing it (#241), said as a
/// toast once no game runs. [gameId]: the game it's about, so a download's
/// news isn't said on that game's own page.
class Notice {
  const Notice(this.text, {this.gameId, this.isDownload = false});

  final String text;
  final String? gameId;
  final bool isDownload;

  factory Notice.downloaded(String gameId, String name) =>
      Notice(tr('{0} is downloaded.', [name]), gameId: gameId, isDownload: true);

  factory Notice.uploaded(int n) =>
      Notice(n == 1 ? tr('Uploaded 1 save that was waiting.') : tr('Uploaded {0} saves that were waiting.', [n]));

  factory Notice.shared(SharedItem item, String gameName) => Notice(
    item.isState
        ? tr('{0} shared a save state of {1}.', [item.username, gameName])
        : tr('{0} shared a save of {1}.', [item.username, gameName]),
    gameId: item.gameId,
  );
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
          username: (item['username'] as String?)?.trim().isNotEmpty == true
              ? (item['username'] as String).trim()
              : tr('Another player'),
          isState: states,
        ),
  ];
}

/// Which other players' shares of which games this profile has seen (#241),
/// in the profile's prefs (`notify.shared`). A game looked at for the first
/// time has everything it holds taken as seen: only what's shared after
/// that is news, not years of old shares at once.
class SharedSeen {
  SharedSeen(this._prefs);

  static const key = 'notify.shared';

  /// The newest ids kept; older ones drop off.
  static const keep = 1000;

  final AppPreferences? _prefs;

  /// One change at a time: games are looked at side by side.
  Future<void> _last = Future.value();

  ({List<String> games, List<String> ids}) _read() {
    try {
      final j = jsonDecode(_prefs?.getString(key) ?? '{}');
      if (j is Map) {
        return (
          games: [for (final g in j['games'] is List ? j['games'] as List : const []) '$g'],
          ids: [for (final i in j['ids'] is List ? j['ids'] as List : const []) '$i'],
        );
      }
    } on FormatException {
      // A damaged list starts again.
    }
    return (games: <String>[], ids: <String>[]);
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
    final seen = _read();
    final known = seen.games.contains(gameId);
    final fresh = [
      for (final i in items)
        if (!seen.ids.contains(i.key)) i,
    ];
    if (known && fresh.isEmpty) return const [];
    final games = [gameId, ...seen.games.where((g) => g != gameId)].take(keep).toList();
    final ids = [...fresh.map((i) => i.key), ...seen.ids].take(keep).toList();
    await prefs.setString(key, jsonEncode({'games': games, 'ids': ids}));
    return known ? fresh : const [];
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
