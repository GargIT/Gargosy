/// What a RomM user may change in the library (#245), and the admin tools'
/// models: a scan's progress, a metadata match to pick.
library;

/// What the profile's RomM user may do to the library, from RomM 5.4's
/// `/api/permissions/me` (its UI action keys), else an older RomM's role.
class RommRights {
  const RommRights({this.scan = false, this.upload = false, this.match = false, this.deleteGames = false});

  /// Nothing (offline, unreadable, a viewer).
  static const none = RommRights();

  /// `library.scan`: Settings → RomM library → Scan library.
  final bool scan;

  /// `rom.upload`: a platform's Upload a game.
  final bool upload;

  /// `rom.match`: the game page's ⋯ → Fix match.
  final bool match;

  /// `rom.delete`: the game page's ⋯ → Delete from RomM (#135).
  final bool deleteGames;

  bool get any => scan || upload || match || deleteGames;

  /// RomM 5.4's answer: an admin may do everything; else the action keys.
  factory RommRights.fromPermissions(Map<dynamic, dynamic> data) {
    if (data['is_admin'] == true) return const RommRights(scan: true, upload: true, match: true, deleteGames: true);
    final grants = data['grants'];
    final keys = {
      if (grants is List)
        for (final g in grants)
          if (g is Map && g['action'] is String) g['action'] as String,
    };
    return RommRights(
      scan: keys.contains('library.scan'),
      upload: keys.contains('rom.upload'),
      match: keys.contains('rom.match'),
      deleteGames: keys.contains('rom.delete'),
    );
  }

  /// An older RomM without `/api/permissions/me`: an admin or an editor
  /// changes the library.
  factory RommRights.fromRole(Object? role) => role == 'admin' || role == 'editor'
      ? const RommRights(scan: true, upload: true, match: true, deleteGames: true)
      : none;
}

/// RomM refused an admin call: [message] says why, in words for the player
/// (RomM's own `detail` when it gave one).
class RommAdminRefused implements Exception {
  const RommAdminRefused(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

/// How much a scan looks at: new files only, or everything again.
enum ScanKind {
  quick('quick'),
  complete('complete');

  const ScanKind(this.wire);

  /// RomM's `type`.
  final String wire;
}

/// A scan task as RomM tells it (`GET /api/tasks/{id}`).
class ScanProgress {
  const ScanProgress({
    required this.status,
    this.totalPlatforms = 0,
    this.scannedPlatforms = 0,
    this.totalGames = 0,
    this.scannedGames = 0,
    this.newGames = 0,
    this.identifiedGames = 0,
  });

  /// RQ's job status: queued, started, finished, failed, stopped, canceled …
  final String status;
  final int totalPlatforms;
  final int scannedPlatforms;
  final int totalGames;
  final int scannedGames;
  final int newGames;
  final int identifiedGames;

  bool get running => const {'queued', 'started', 'deferred', 'scheduled'}.contains(status);
  bool get finished => status == 'finished';

  factory ScanProgress.fromJson(Map<dynamic, dynamic> json) {
    final meta = json['meta'];
    final stats = meta is Map ? meta['scan_stats'] : null;
    int n(String key) => stats is Map && stats[key] is num ? (stats[key] as num).toInt() : 0;
    return ScanProgress(
      status: json['status'] as String? ?? 'queued',
      totalPlatforms: n('total_platforms'),
      scannedPlatforms: n('scanned_platforms'),
      totalGames: n('total_roms'),
      scannedGames: n('scanned_roms'),
      newGames: n('new_roms'),
      identifiedGames: n('identified_roms'),
    );
  }
}

/// A game a metadata source knows, offered for Fix match
/// (`GET /api/search/roms`).
class MatchCandidate {
  const MatchCandidate({required this.name, required this.ids, this.summary = '', this.cover = ''});

  final String name;
  final String summary;

  /// The cover to set: the first source's that has one.
  final String cover;

  /// Each source's id for it, by RomM's form field (`igdb_id` …); the
  /// sources that don't know it are left out.
  final Map<String, String> ids;

  /// The ids Fix match sets; one the match lacks is cleared, so an old
  /// wrong match from another source doesn't stay (as RomM's own dialog does).
  static const matchFields = [
    'igdb_id',
    'ss_id',
    'moby_id',
    'flashpoint_id',
    'launchbox_id',
    'libretro_id',
    'steam_id',
  ];

  static const _covers = [
    'igdb_url_cover',
    'ss_url_cover',
    'moby_url_cover',
    'flashpoint_url_cover',
    'launchbox_url_cover',
    'libretro_url_cover',
    'steam_url_cover',
  ];

  /// The sources' names, for the list ("IGDB · ScreenScraper").
  static const sourceNames = {
    'igdb_id': 'IGDB',
    'ss_id': 'ScreenScraper',
    'moby_id': 'MobyGames',
    'flashpoint_id': 'Flashpoint',
    'launchbox_id': 'LaunchBox',
    'libretro_id': 'Libretro',
    'steam_id': 'Steam',
  };

  List<String> get sources => [
    for (final f in matchFields)
      if (ids.containsKey(f)) sourceNames[f]!,
  ];

  static MatchCandidate? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final ids = <String, String>{
      for (final f in matchFields)
        if (json[f] case final v? when v != 0 && '$v'.isNotEmpty) f: '$v',
    };
    if (ids.isEmpty) return null;
    var cover = '';
    for (final c in _covers) {
      if (json[c] case final String url when url.isNotEmpty) {
        cover = url;
        break;
      }
    }
    return MatchCandidate(name: name, ids: ids, summary: json['summary'] as String? ?? '', cover: cover);
  }

  /// The cover the game gets: IGDB's large size instead of the list's
  /// (as RomM's own dialog does).
  String get coverForGame => cover.replaceAll('t_cover_big', 't_1080p');
}
