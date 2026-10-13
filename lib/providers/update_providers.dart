import 'package:flutter/foundation.dart';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:pub_semver/pub_semver.dart';

import '../core/constants/app_constants.dart';
import '../core/platform/platform_info.dart';
import '../profiles/profile_providers.dart';
import '../update/update_checker.dart';
import '../update/update_downloader.dart';
import '../update/update_installer.dart';
import '../update/update_version.dart';

/// Gargosy's own command line (main's `args`), passed on by an update.
final launchArgsProvider = Provider<List<String>>((ref) => const []);

/// What the last update did, read from [launchArgsProvider] in main.
final updateOutcomeProvider = Provider<UpdateOutcome?>((ref) => null);

/// Whether Gargosy checks for updates by itself at start; tests turn it off.
final updateAutoCheckEnabledProvider = Provider<bool>((ref) => true);

/// Ends Gargosy the normal way (Hive closed, settings already written), so
/// the updater can replace its files; tests replace it.
final appQuitProvider = Provider<Future<void> Function()>((ref) => () async {
      await Hive.close();
      io.exit(0);
    });

final installedVersionProvider =
    Provider<Version>((ref) => UpdateVersion.parse(AppConstants.version) ?? Version.none);

/// A Dio for GitHub; tests replace it.
final updateDioProvider = Provider<Dio>((ref) => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      headers: {'User-Agent': 'Gargosy/${AppConstants.version}'},
    )));

final updateCheckerProvider = Provider<UpdateChecker>((ref) => UpdateChecker(
      dio: ref.watch(updateDioProvider),
      prefs: ref.watch(appPreferencesProvider),
      installed: ref.watch(installedVersionProvider),
    ));

final updateDownloaderProvider = Provider<UpdateDownloader>(
    (ref) => UpdateDownloader(dio: ref.watch(updateDioProvider), root: ref.watch(appRootProvider)));

final updateInstallerProvider = Provider<UpdateInstaller>((ref) => UpdateInstaller(
      root: ref.watch(appRootProvider),
      pid: io.pid,
      args: ref.watch(launchArgsProvider),
      currentVersion: AppConstants.version,
      platform: PlatformInfo.current,
    ));

/// The update check as the UI shows it.
class UpdateState {
  const UpdateState({this.checking = false, this.result});
  final bool checking;

  /// The last check's answer this session, or null before one.
  final UpdateCheck? result;

  UpdateAvailable? get available => result is UpdateAvailable ? result as UpdateAvailable : null;
}

class UpdateNotifier extends StateNotifier<UpdateState> {
  UpdateNotifier(this._ref) : super(const UpdateState());
  final Ref _ref;

  UpdateChecker get _checker => _ref.read(updateCheckerProvider);

  /// The check at start: at most one, none within 6 h of the last, and none
  /// when it's switched off.
  Future<void> startupCheck() async {
    if (!_ref.read(updateAutoCheckEnabledProvider) || !_checker.autoCheck) return;
    await _check(force: false);
  }

  /// Check now.
  Future<void> checkNow() => _check(force: true);

  Future<void> setChannel(UpdateChannel c) async {
    if (c == _checker.channel) return;
    await _checker.setChannel(c);
    _generation++; // a check still running for the old channel is dropped
    state = const UpdateState();
    await _check(force: true);
  }

  Future<void> setAutoCheck(bool on) async {
    await _checker.setAutoCheck(on);
    state = UpdateState(checking: state.checking, result: state.result);
  }

  /// Bumped by [setChannel]: an answer for an older channel isn't shown.
  int _generation = 0;

  Future<void> _check({required bool force}) async {
    if (state.checking) return;
    final generation = _generation;
    state = UpdateState(checking: true, result: state.result);
    UpdateCheck? result;
    try {
      result = await _checker.check(force: force);
    } catch (e) {
      debugPrint('[Update] check failed: $e');
    } finally {
      if (mounted && generation == _generation) state = UpdateState(result: result ?? state.result);
    }
  }
}

final updateStateProvider = StateNotifierProvider<UpdateNotifier, UpdateState>((ref) => UpdateNotifier(ref));
