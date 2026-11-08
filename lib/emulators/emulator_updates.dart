import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/app_preferences.dart';
import '../profiles/profile_providers.dart';
import '../providers/update_providers.dart';
import 'emulator_installer.dart';
import 'emulator_library.dart';

/// Which installed emulators have a newer release (#243): each one's newest
/// download (`EmulatorInstaller.latestUrl`) against the one it was installed
/// from (`.gargosy-install.json`). At most one check in [every] unless
/// forced; what it found is kept in app-wide prefs, so the next start shows
/// it without asking again. Never installs anything itself.
class EmulatorUpdateCheck {
  EmulatorUpdateCheck({required this.prefs, required this.latestUrl, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppPreferences prefs;

  /// An emulator's newest download (`EmulatorInstaller.latestUrl`).
  final Future<String?> Function(String id) latestUrl;
  final DateTime Function() _clock;

  /// When the last check that reached a release list ran.
  static const lastKey = 'emulators.updateCheck.last';

  /// What it found: `{emulator id: newest download}`, as JSON.
  static const foundKey = 'emulators.updateCheck.found';

  static const every = Duration(hours: 24);

  /// An emulator whose newest release can be told: installed by a download
  /// Gargosy knows (not imported), and offered for download now.
  static bool checkable(EmulatorInfo e) =>
      e.supported &&
      e.installedExe != null &&
      e.downloadOff == null &&
      e.installedFrom != null &&
      e.installedFrom != EmulatorLibrary.imported;

  DateTime? get lastCheck => DateTime.tryParse(prefs.getString(lastKey) ?? '');

  /// What the last check found, of the emulators in [installed] it still
  /// holds for (one updated or removed since drops out).
  Map<String, String> remembered(List<EmulatorInfo> installed) {
    final stored = _stored();
    return {
      for (final e in installed)
        if (checkable(e) && stored[e.id] != null && stored[e.id] != e.installedFrom) e.id: stored[e.id]!,
    };
  }

  /// Checks [installed] (unless one ran within [every] and it isn't
  /// [force]d) and gives the emulators with a newer release, by id. An
  /// emulator whose release list can't be read keeps what was found before;
  /// when none could be read (offline), the next start checks again.
  Future<Map<String, String>> check(List<EmulatorInfo> installed, {bool force = false}) async {
    final last = lastCheck;
    if (!force && last != null && _clock().difference(last) < every) return remembered(installed);
    final before = _stored();
    final found = <String, String>{};
    var reached = false;
    for (final e in installed.where(checkable)) {
      try {
        final latest = await latestUrl(e.id);
        reached = true;
        if (latest != null && latest != e.installedFrom) found[e.id] = latest;
      } on Object catch (err) {
        debugPrint('[EmulatorUpdates] ${e.id}: newest release not read: $err');
        final kept = before[e.id];
        if (kept != null && kept != e.installedFrom) found[e.id] = kept;
      }
    }
    await prefs.setString(foundKey, jsonEncode(found));
    if (reached) await prefs.setString(lastKey, _clock().toUtc().toIso8601String());
    debugPrint('[EmulatorUpdates] ${found.isEmpty ? 'none newer' : 'newer: ${found.keys.join(', ')}'}');
    return found;
  }

  Map<String, String> _stored() {
    try {
      final json = jsonDecode(prefs.getString(foundKey) ?? '{}');
      if (json is! Map) return const {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (key is String && value is String) key: value,
      };
    } on FormatException {
      return const {};
    }
  }
}

/// The check as the UI shows it: the emulators with a newer release, by id.
class EmulatorUpdatesState {
  const EmulatorUpdatesState({this.checking = false, this.available = const {}});
  final bool checking;
  final Map<String, String> available;
}

class EmulatorUpdatesNotifier extends StateNotifier<EmulatorUpdatesState> {
  EmulatorUpdatesNotifier(this._ref) : super(const EmulatorUpdatesState());
  final Ref _ref;

  EmulatorUpdateCheck? get _check {
    final installer = _ref.read(emulatorInstallerProvider);
    if (installer == null) return null;
    return EmulatorUpdateCheck(prefs: _ref.read(appPreferencesProvider), latestUrl: installer.latestUrl);
  }

  /// The check when a profile opens: none when Gargosy's own check at start
  /// is off, at most one in 24 h. Never throws.
  Future<void> startupCheck() async {
    try {
      if (!_ref.read(updateAutoCheckEnabledProvider) || !_ref.read(updateCheckerProvider).autoCheck) return;
    } on Object catch (e) {
      debugPrint('[EmulatorUpdates] not checked: $e');
      return;
    }
    await _run(force: false);
  }

  /// Settings → Emulators' Check for updates. Never throws.
  Future<void> checkNow() => _run(force: true);

  /// After an install or a remove: what was found, against the emulators
  /// as they are now. Never throws.
  Future<void> refresh() async {
    try {
      final check = _check;
      if (check == null) return;
      final list = await _ref.read(emulatorsProvider.future);
      if (mounted) state = EmulatorUpdatesState(checking: state.checking, available: check.remembered(list));
    } on Object catch (e) {
      debugPrint('[EmulatorUpdates] not refreshed: $e');
    }
  }

  Future<void> _run({required bool force}) async {
    if (state.checking) return;
    final EmulatorUpdateCheck? check;
    try {
      check = _check;
    } on Object catch (e) {
      debugPrint('[EmulatorUpdates] not checked: $e');
      return;
    }
    if (check == null) return;
    state = EmulatorUpdatesState(checking: true, available: state.available);
    var available = state.available;
    try {
      available = await check.check(await _ref.read(emulatorsProvider.future), force: force);
    } on Object catch (e) {
      debugPrint('[EmulatorUpdates] check failed: $e');
    } finally {
      if (mounted) state = EmulatorUpdatesState(available: available);
    }
  }
}

final emulatorUpdatesProvider = StateNotifierProvider<EmulatorUpdatesNotifier, EmulatorUpdatesState>(
  (ref) => EmulatorUpdatesNotifier(ref),
);
