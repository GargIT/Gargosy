// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy: lints the newer SDK raises on copied code, kept as upstream.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../emulator/emulator_strategy.dart';
import '../romm/romm_models.dart';
import '../romm/romm_state.dart';
import '../storage/app_preferences.dart';
import 'catalog/save_entry.dart' show SaveOwner;
import 'save_state_info.dart';
import 'save_strategy.dart';
import 'state_sync_capable.dart';
import 'state_sync_record.dart';
import 'state_sync_service.dart';
import '../../l10n/tr.dart';

/// Where a resumable state is.
enum ResumeWhere { thisPc, romm, both }

/// One save state the game can be resumed from.
@immutable
class ResumeEntry {
  const ResumeEntry({
    required this.emulatorId,
    required this.emulatorName,
    required this.fileName,
    required this.slot,
    required this.savedAt,
    required this.where,
    this.newerOnRomm = false,
    this.emulatorVersion,
    this.stateFormat,
    this.installedVersion,
    this.compat = StateCompat.unknown,
    this.localFile,
    this.remoteId,
    this.remoteUpdatedAt,
    this.remoteScreenshotUrl,
    this.romPath,
    this.resumable = true,
    this.core,
    this.owner,
    this.shared = false,
  });

  final String emulatorId;
  final String emulatorName;

  /// Gargosy: the emulator can start the game in this state. False for an
  /// emulator that syncs states but has no option to load one at start
  /// (Azahar, melonDS): listed, loaded from the emulator's own menu.
  final bool resumable;
  final String fileName;
  final StateSlot slot;
  final DateTime savedAt;
  final ResumeWhere where;

  /// On both sides and the server copy changed since the last sync: the
  /// pre-launch pull will replace the local copy. [emulatorVersion] is then
  /// null (unknown until downloaded).
  final bool newerOnRomm;
  final String? emulatorVersion;

  /// The emulator's own state-format id, shown when the state doesn't record
  /// [emulatorVersion]. Display only; null when unknown, like the version.
  final String? stateFormat;
  final String? installedVersion;
  final StateCompat compat;
  final io.File? localFile;
  final int? remoteId;
  final String? remoteUpdatedAt;
  final String? remoteScreenshotUrl;

  /// The ROM file the state was identified with. A state belongs to one disc
  /// (its serial), so a resume boots exactly this file.
  final String? romPath;

  /// Gargosy: the core the state belongs to (RetroArch: `pcsx_rearmed`,
  /// whose folder it was found in); a resume starts that core. Null for an
  /// emulator without cores.
  final String? core;

  /// Gargosy (#92): another player's state, shared on RomM ([remoteId] is
  /// theirs); null for the player's own. Resuming it starts from a copy:
  /// theirs never changes.
  final SaveOwner? owner;

  /// Gargosy (#92): the player's own state on RomM, shared with the other
  /// players there.
  final bool shared;
}

/// The outcome of [ResumeService.checkBeforeLaunch].
sealed class ResumeCheck {
  const ResumeCheck();
}

/// Load `path`. `stale`: a newer RomM copy was expected but did not arrive,
/// so the older local copy is loaded. `prompt`: ask before loading.
final class ResumeReady extends ResumeCheck {
  const ResumeReady(this.path, {this.stale = false, this.prompt});
  final String path;
  final bool stale;
  final ({String stateVersion, String installed})? prompt;
}

/// The chosen state is not on disk: nothing may be launched.
final class ResumeMissing extends ResumeCheck {
  const ResumeMissing();
}

/// What to tell the user when the chosen state turned out missing right
/// before launch ([ResumeMissing]), or when there was no resume service to
/// check it with ([serviceAvailable] false).
String resumeMissingMessage(ResumeEntry entry, {required bool serviceAvailable}) {
  if (!serviceAvailable) return tr('Resume isn\'t available right now. Nothing was started.');
  final fromRomm = entry.where == ResumeWhere.romm || entry.newerOnRomm;
  return fromRomm
      ? tr('Couldn\'t get {0} from RomM. Nothing was started.', [entry.slot.label])
      : tr('Couldn\'t find {0} on this PC. Nothing was started.', [entry.slot.label]);
}

/// One emulator's view of one ROM file: a multi-disc game has one source per
/// emulator and disc, each accepting only its own disc's states.
class _Source {
  _Source(this.emulator, this.strategy, this.dir, this.matches, this.installed, this.romPath, this.core);
  final EmulatorStrategy emulator;
  final StateSyncCapable strategy;
  final io.Directory dir;
  final bool Function(String) matches;
  final String? installed;
  final String romPath;
  final String? core;
}

/// Answers "what can this game be resumed from, and with which emulator?".
/// Emulator-agnostic: every emulator detail comes from [EmulatorStrategy] and
/// [StateSyncCapable].
class ResumeService {
  ResumeService({
    required List<EmulatorStrategy> Function(String platformSlug) emulatorsFor,
    required SaveStrategy? Function(Game game, {String? emulatorId}) resolveSaveStrategy,
    required AppPreferences prefs,
    RommStatesApi? api,
    bool Function()? isOffline,
    Duration listTimeout = StateSyncService.defaultListTimeout,
    StrategyExclusive? exclusive,
    Future<void> Function(EmulatorStrategy emulator)? prepareFolders,
    Future<List<Map<String, dynamic>>?> Function(String romId)? sharedStates,
  }) : _emulatorsFor = emulatorsFor,
       _sharedStates = sharedStates,
       _prepareFolders = prepareFolders,
       _exclusive = exclusive,
       _resolve = resolveSaveStrategy,
       _prefs = prefs,
       _records = StateRecordStore(prefs),
       _api = api,
       _isOffline = isOffline ?? (() => false),
       _listTimeout = listTimeout;

  final List<EmulatorStrategy> Function(String) _emulatorsFor;
  final SaveStrategy? Function(Game, {String? emulatorId}) _resolve;
  final AppPreferences _prefs;
  final StateRecordStore _records;
  final RommStatesApi? _api;
  final bool Function() _isOffline;
  final Duration _listTimeout;

  /// The save lock: finding a game's states sets up the shared strategies.
  final StrategyExclusive? _exclusive;

  /// Gargosy: makes an installed emulator's folders in the profile, as its
  /// first launch would. A profile that never ran it has none, and its
  /// strategy can't name a state folder, so RomM's states would have no owner.
  final Future<void> Function(EmulatorStrategy emulator)? _prepareFolders;

  /// Gargosy (#92): other players' public states of a game (RomM's
  /// `all_user_states`, the profile's own left out); null when unread.
  final Future<List<Map<String, dynamic>>?> Function(String romId)? _sharedStates;
  final Map<String, Uint8List?> _thumbnails = {};

  /// Save strategy per emulator id, as last resolved by [_sources]; used for
  /// local thumbnails (a strategy's screenshot reader does not depend on the game).
  final Map<String, StateSyncCapable> _strategyByEmulator = {};

  /// Local entries first, then (when some emulator syncs states and RomM is
  /// reachable) the list merged with RomM's. [romPaths] are the game's ROM
  /// files (every disc of a multi-disc game); each entry's `romPath` is the
  /// one its state belongs to. When several ROM files of the same emulator
  /// claim a state (the tracks of a cue/bin disc, two copies of one disc),
  /// the first in path order owns it, so it is listed once. Never errors.
  Stream<List<ResumeEntry>> entriesFor(Game game, List<String> romPaths) async* {
    final sources = <_Source>[];
    final versions = <String, String?>{}; // installed version per emulator, asked once
    for (final romPath in [...romPaths]..sort()) {
      sources.addAll(await _sources(game, romPath, versions));
    }
    final local = <String, ResumeEntry>{};
    for (final source in sources) {
      for (final entry in (await _localEntries(source)).entries) {
        local.putIfAbsent(entry.key, () => entry.value);
      }
    }
    yield _sorted(local.values);

    final own = await _withRomm(game, sources, local);
    if (own != null) yield _sorted(own.values);
    final shared = await _sharedEntries(game, sources);
    if (shared.isNotEmpty) yield [..._sorted((own ?? local).values), ..._sorted(shared)];
  }

  /// Gargosy (#92): other players' public states the game's emulators can
  /// tell as theirs, each with its [ResumeEntry.owner]. Listed with state
  /// sync off too: resuming one only downloads it. Never throws.
  Future<List<ResumeEntry>> _sharedEntries(Game game, List<_Source> sources) async {
    final read = _sharedStates;
    if (read == null || sources.isEmpty || _isOffline()) return const [];
    final List<Map<String, dynamic>>? items;
    try {
      items = await read(game.id).timeout(_listTimeout);
    } catch (e) {
      debugPrint("[Resume] ${game.name}: other players' states not listed: $e");
      return const [];
    }
    final result = <ResumeEntry>[];
    for (final item in items ?? const <Map<String, dynamic>>[]) {
      final RommState state;
      try {
        state = RommState.fromJson(item);
      } catch (_) {
        continue;
      }
      final source = _ownerOf(state, sources, sources);
      if (source == null || !_listed(source.emulator, state.fileName)) continue;
      final avatar = item['user_avatar_path']?.toString() ?? '';
      result.add(
        ResumeEntry(
          emulatorId: source.emulator.emulatorId,
          emulatorName: source.emulator.name,
          fileName: state.fileName,
          slot: source.strategy.slotOf(state.fileName),
          savedAt: DateTime.tryParse(state.updatedAt ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
          where: ResumeWhere.romm,
          installedVersion: source.installed,
          remoteId: state.id,
          remoteUpdatedAt: state.updatedAt,
          remoteScreenshotUrl: state.screenshotUrl,
          romPath: source.romPath,
          resumable:
              _resumable(source.emulator, state.fileName) &&
              (source.emulator.loadsStateFromPath || source.strategy.stateFileForSlot(state.fileName, 1) != null),
          core: source.core,
          owner: SaveOwner(
            userId: (item['user_id'] as num?)?.toInt() ?? -1,
            username: item['username']?.toString() ?? '?',
            avatarPath: avatar.isEmpty ? null : avatar,
          ),
        ),
      );
    }
    return result;
  }

  /// [local] merged with the profile's own states on RomM; null when state
  /// sync is off for every source, RomM can't be asked, or its list failed.
  Future<Map<String, ResumeEntry>?> _withRomm(Game game, List<_Source> sources, Map<String, ResumeEntry> local) async {
    // Gargosy: one switch for every emulator whose strategy syncs states (S0.4).
    final syncing = StateSyncService.isOn(_prefs)
        ? sources.where((s) => s.emulator.supportsStateSync).toList()
        : const <_Source>[];
    final api = _api;
    if (api == null || syncing.isEmpty || _isOffline()) return null;
    final List<RommState> remote;
    try {
      remote = await api.listStates(game.id).timeout(_listTimeout);
    } catch (e) {
      debugPrint('[Resume] ${game.name}: RomM list failed, local states only: $e');
      return null;
    }
    final records = _records.load(game.id);
    final merged = Map<String, ResumeEntry>.of(local);
    for (final state in remote) {
      final owner = _ownerOf(state, sources, syncing);
      if (owner == null || !_listed(owner.emulator, state.fileName)) continue;
      final key = _key(owner.emulator.emulatorId, state.fileName);
      final remoteTime = DateTime.tryParse(state.updatedAt ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
      final existing = merged[key];
      final record = records[state.fileName];
      if (existing == null) {
        // Synced once and since deleted on this PC: the pull deliberately
        // never restores it, so resuming it could only fail.
        if (record != null && record.hasSynced) continue;
        merged[key] = ResumeEntry(
          emulatorId: owner.emulator.emulatorId,
          emulatorName: owner.emulator.name,
          fileName: state.fileName,
          slot: owner.strategy.slotOf(state.fileName),
          savedAt: remoteTime,
          where: ResumeWhere.romm,
          installedVersion: owner.installed,
          remoteId: state.id,
          remoteUpdatedAt: state.updatedAt,
          remoteScreenshotUrl: state.screenshotUrl,
          romPath: owner.romPath,
          resumable: _resumable(owner.emulator, state.fileName),
          core: owner.core,
          shared: state.isPublic,
        );
        continue;
      }
      final newer = record != null && (record.rommStateId != state.id || record.serverUpdatedAt != state.updatedAt);
      merged[key] = ResumeEntry(
        emulatorId: existing.emulatorId,
        emulatorName: existing.emulatorName,
        fileName: existing.fileName,
        slot: existing.slot,
        savedAt: newer && remoteTime.isAfter(existing.savedAt) ? remoteTime : existing.savedAt,
        where: ResumeWhere.both,
        newerOnRomm: newer,
        emulatorVersion: newer ? null : existing.emulatorVersion,
        stateFormat: newer ? null : existing.stateFormat,
        installedVersion: existing.installedVersion,
        compat: newer ? StateCompat.unknown : existing.compat,
        localFile: existing.localFile,
        remoteId: state.id,
        remoteUpdatedAt: state.updatedAt,
        remoteScreenshotUrl: state.screenshotUrl,
        romPath: existing.romPath,
        resumable: existing.resumable,
        core: existing.core,
        shared: state.isPublic,
      );
    }
    return merged;
  }

  /// Gargosy (#94): the files of the player's own state [entry] on this PC
  /// (the state and what belongs to it, e.g. its screenshot), to delete.
  List<io.File> localFilesOf(ResumeEntry entry) {
    final file = entry.localFile;
    if (file == null) return const [];
    final strategy = _strategyByEmulator[entry.emulatorId];
    return [
      file,
      for (final name in strategy?.stateSidecars(p.basename(file.path)) ?? const <String>[])
        io.File(p.join(file.parent.path, name)),
    ];
  }

  /// Gargosy (#94): forgets the sync record of [game]'s state [fileName],
  /// deleted by the player: nothing of it is left to sync.
  Future<void> forgetState(Game game, String fileName) async {
    final records = _records.load(game.id);
    if (records.remove(fileName) != null) await _records.save(game.id, records);
  }

  /// Gargosy (#92): another player's state [entry], downloaded and checked
  /// as the emulator's. Throws with the reason when it can't be.
  Future<Uint8List> downloadShared(ResumeEntry entry, Game game) async {
    final api = _api;
    final id = entry.remoteId;
    if (api == null || id == null) throw StateError(tr('RomM can\'t be reached'));
    final bytes = await api.downloadState(id);
    final strategy = _resolve(game, emulatorId: entry.emulatorId);
    if (strategy is StateSyncCapable && !strategy.looksLikeValidState(bytes)) {
      throw StateError(tr('it isn\'t a {0} state', [entry.emulatorName]));
    }
    return bytes;
  }

  /// Gargosy (#92): where another player's state [entry] goes for an
  /// emulator that resumes by slot: the first slot from 1 the player has
  /// nothing in, on this PC or synced before (a slot deleted on this PC
  /// stays the player's). Throws when every slot is taken.
  Future<String> freeSlotFor(ResumeEntry entry, Game game, String romPath) async {
    final sources = await _sources(game, romPath, {});
    final source = _firstWhereOrNull(sources, (s) => s.emulator.emulatorId == entry.emulatorId);
    if (source == null) throw StateError(tr('{0} can\'t find the game\'s states', [entry.emulatorName]));
    final records = _records.load(game.id);
    for (var slot = 1; slot <= 9; slot++) {
      final name = source.strategy.stateFileForSlot(entry.fileName, slot);
      if (name == null) continue;
      if (records.containsKey(name) || await io.File(p.join(source.dir.path, name)).exists()) continue;
      return p.join(source.dir.path, name);
    }
    throw StateError(tr('every {0} state slot of yours is in use', [entry.emulatorName]));
  }

  /// Checks the chosen state right before launch (after the pre-launch pull).
  /// [pulled] and [conflicted] are the file names that pull downloaded and
  /// reported as conflicts; both null when no pull ran.
  Future<ResumeCheck> checkBeforeLaunch(
    ResumeEntry entry,
    Game game,
    String romPath, {
    Set<String>? pulled,
    Set<String>? conflicted,
  }) async {
    final sources = await _sources(game, romPath, {});
    final source = _firstWhereOrNull(sources, (s) => s.emulator.emulatorId == entry.emulatorId);
    if (source == null) return const ResumeMissing();
    final file = io.File(p.join(source.dir.path, entry.fileName));
    try {
      if (!await file.exists() || await file.length() < StateSyncService.minValidStateBytes) {
        debugPrint('[Resume] ${entry.fileName} missing after pull: aborting');
        return const ResumeMissing();
      }
    } catch (e) {
      debugPrint('[Resume] ${entry.fileName}: cannot check the file after pull: $e');
      return const ResumeMissing();
    }
    // describeState/installedVersion are contractually not supposed to
    // throw, but a strategy implementation could still break that: fall back
    // to "version unknown" (no prompt) rather than losing the resume launch.
    String? stateVersion;
    String? installed;
    try {
      stateVersion = (await source.strategy.describeState(file)).emulatorVersion;
      installed = source.installed;
    } catch (e) {
      debugPrint('[Resume] ${entry.fileName}: version check failed, treating as unknown: $e');
    }
    final compat = compatOf(stateVersion, installed);
    // "Seen" only when the list itself showed the mismatch (its warning) for
    // this very state version; an emulator updated since the list must ask.
    final seen =
        entry.compat == StateCompat.mismatch &&
        entry.emulatorVersion != null &&
        stateVersion != null &&
        sameEmulatorVersion(entry.emulatorVersion!, stateVersion);
    final prompt = compat == StateCompat.mismatch && !seen
        ? (stateVersion: stateVersion!, installed: installed!)
        : null;
    // Stale: a newer RomM copy was expected but the pull did not bring it
    // down. A conflict is not stale: the copy on disk is the user's choice.
    final stale =
        entry.newerOnRomm &&
        !(pulled?.contains(entry.fileName) ?? false) &&
        !(conflicted?.contains(entry.fileName) ?? false);
    debugPrint(
      '[Resume] version ${stateVersion ?? 'unknown'} vs installed '
      '${installed ?? 'unknown'}: ${prompt != null ? 'asking' : compat.name}',
    );
    return ResumeReady(file.path, stale: stale, prompt: prompt);
  }

  @visibleForTesting
  int get thumbnailCacheSize => _thumbnails.length;

  /// Thumbnail for [entry] (local via the emulator, remote via RomM). Null on
  /// any failure. Successful results (including "this state has no
  /// screenshot") are cached for the session, at most [_thumbnailCacheLimit]
  /// of them; a failure is not, so the next call tries again.
  Future<Uint8List?> thumbnailFor(ResumeEntry entry) async {
    final key = '${entry.emulatorId}|${entry.fileName}|${entry.savedAt.millisecondsSinceEpoch}';
    if (_thumbnails.containsKey(key)) return _thumbnails[key];
    Uint8List? bytes;
    try {
      final local = entry.localFile;
      if (local != null && !entry.newerOnRomm) {
        bytes = await _strategyByEmulator[entry.emulatorId]?.stateScreenshot(local);
      } else if (entry.remoteScreenshotUrl != null && _api != null) {
        bytes = await _api.downloadStateScreenshot(entry.remoteScreenshotUrl!);
      }
    } catch (e) {
      debugPrint('[Resume] thumbnail for ${entry.fileName} failed: $e');
      return null;
    }
    _thumbnails.remove(key);
    _thumbnails[key] = bytes;
    while (_thumbnails.length > _thumbnailCacheLimit) {
      _thumbnails.remove(_thumbnails.keys.first); // oldest first (insertion order)
    }
    return bytes;
  }

  static const int _thumbnailCacheLimit = 32;

  /// [versions] caches each emulator's installed version for the caller's
  /// run (one question per emulator, not per disc).
  Future<List<_Source>> _sources(Game game, String romPath, Map<String, String?> versions) {
    final exclusive = _exclusive;
    return exclusive == null
        ? _sourcesUnlocked(game, romPath, versions)
        : exclusive(() => _sourcesUnlocked(game, romPath, versions));
  }

  Future<List<_Source>> _sourcesUnlocked(Game game, String romPath, Map<String, String?> versions) async {
    final result = <_Source>[];
    for (final emulator in _emulatorsFor(game.platformSlug ?? '')) {
      // Gargosy: an emulator that syncs states without loading one at start
      // is listed too, its states not resumable.
      if (!emulator.supportsStateLoadOnLaunch && !emulator.supportsStateSync) continue;
      try {
        if (emulator.supportsStateSync && StateSyncService.isOn(_prefs)) {
          await _prepareFolders?.call(emulator);
        }
        final strategy = _resolve(game, emulatorId: emulator.emulatorId);
        if (strategy is! StateSyncCapable) continue;
        final matches = await strategy.stateFileMatcher(game, romPath);
        if (matches == null) {
          debugPrint('[Resume] ${game.name}: ${emulator.emulatorId} cannot identify the game');
          continue;
        }
        final dir = io.Directory(await strategy.stateDirectory(game, romPath));
        final core = strategy.stateCoreFor(game);
        _strategyByEmulator[emulator.emulatorId] = strategy;
        final id = emulator.emulatorId;
        final installed = versions.containsKey(id) ? versions[id] : (versions[id] = await emulator.installedVersion());
        result.add(_Source(emulator, strategy, dir, matches, installed, romPath, core));
      } catch (e) {
        debugPrint('[Resume] ${game.name}: ${emulator.emulatorId} skipped: $e');
      }
    }
    return result;
  }

  Future<Map<String, ResumeEntry>> _localEntries(_Source source) async {
    final result = <String, ResumeEntry>{};
    try {
      if (!await source.dir.exists()) return result;
      await for (final entity in source.dir.list(followLinks: false)) {
        if (entity is! io.File) continue;
        final name = p.basename(entity.path);
        if (!source.matches(name) || !_listed(source.emulator, name)) continue;
        if (await entity.length() < StateSyncService.minValidStateBytes) continue;
        final info = await source.strategy.describeState(entity);
        result[_key(source.emulator.emulatorId, name)] = ResumeEntry(
          emulatorId: source.emulator.emulatorId,
          emulatorName: source.emulator.name,
          fileName: name,
          slot: source.strategy.slotOf(name),
          savedAt: info.savedAt,
          where: ResumeWhere.thisPc,
          emulatorVersion: info.emulatorVersion,
          stateFormat: info.formatId,
          installedVersion: source.installed,
          compat: compatOf(info.emulatorVersion, source.installed),
          localFile: entity,
          romPath: source.romPath,
          resumable: _resumable(source.emulator, name),
          core: source.core,
        );
      }
    } catch (e) {
      debugPrint('[Resume] listing ${source.dir.path} failed: $e');
    }
    return result;
  }

  /// A state [name] is listed: any of an emulator that syncs states or can't
  /// load them at start (one its command line can't load, as RetroArch's
  /// auto slot, is loaded from the emulator's menu), else only those its
  /// command line loads.
  static bool _listed(EmulatorStrategy e, String name) =>
      e.supportsStateSync || !e.supportsStateLoadOnLaunch || e.canLoadState(name);

  static bool _resumable(EmulatorStrategy e, String name) => e.supportsStateLoadOnLaunch && e.canLoadState(name);

  /// The source a RomM state belongs to: among the sources whose matcher
  /// accepts the name (only those of the tagged emulator when its `emulator`
  /// tag is one of ours), the first, provided they are all the same emulator
  /// ([all] is in ROM path order, see [entriesFor]). Candidates of different
  /// emulators, or none, is no owner.
  _Source? _ownerOf(RommState state, List<_Source> all, List<_Source> syncing) {
    final name = state.fileName;
    if (!StateSyncService.isSafeStateName(name)) return null;
    final tag = state.emulator?.toLowerCase();
    var candidates = all.where((s) => s.matches(name)).toList();
    if (all.any((s) => s.emulator.emulatorId.toLowerCase() == tag)) {
      candidates = candidates.where((s) => s.emulator.emulatorId.toLowerCase() == tag).toList();
    }
    if (candidates.isEmpty) return null;
    final owner = candidates.first;
    if (candidates.any((s) => s.emulator.emulatorId != owner.emulator.emulatorId)) return null;
    return syncing.contains(owner) ? owner : null;
  }

  static String _key(String emulatorId, String fileName) => '$emulatorId|$fileName';

  static T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  static List<ResumeEntry> _sorted(Iterable<ResumeEntry> entries) =>
      entries.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
}
