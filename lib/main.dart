import 'dart:async';
import 'dart:io' as io;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'app.dart';
import 'changelog/whats_new.dart';
import 'core/constants/app_constants.dart';
import 'core/platform/window_service.dart';
import 'core/storage/file_log_sink.dart';
import 'core/storage/gargosy_path_provider.dart';
import 'core/storage/logger_service.dart';
import 'core/storage/json_file_preferences_store.dart';
import 'core/storage/shared_preferences_app_preferences.dart';
import 'library/image_cache.dart';
import 'profiles/app_root.dart';
import 'profiles/path_guard.dart';
import 'profiles/portable_temp.dart';
import 'profiles/profile_providers.dart';
import 'providers/update_providers.dart';
import 'sigil/sigil_library.dart';
import 'core/platform/platform_info.dart';
import 'update/app_updater.dart';
import 'ui/screens/startup_error_app.dart';
import 'l10n/tr.dart';

Future<void> main(List<String> args) async {
  markAppStart();
  WidgetsFlutterBinding.ensureInitialized();
  // The version from pubspec.yaml: shown in the user menu, sent to RomM and RetroAchievements.
  await AppConstants.init();
  final root = AppRoot.fromArgs(args, io.Platform.resolvedExecutable);
  try {
    await root.ensureLayout();
  } on io.FileSystemException catch (e) {
    runApp(StartupErrorApp(message: '${e.message}: ${e.path ?? root.root}'));
    return;
  }
  startFileLog(root);
  unawaited(removeOldImageCache(root));
  // Saves go through sigil only (#57): without it, Gargosy doesn't start.
  final sigil = SigilLibrary.problem();
  if (sigil != null) {
    LoggerService().error(sigil, null, context: 'Start');
    runApp(StartupErrorApp.sigil(sigil));
    return;
  }
  // Portable: plugins, settings and temp files stay in userdata\, never
  // AppData (spec §3).
  usePortableTemp(p.join(root.appData, 'temp'));
  PathProviderPlatform.instance = GargosyPathProvider(
    appDataDir: root.appData,
    previous: PathProviderPlatform.instance,
  );
  SharedPreferencesStorePlatform.instance = JsonFilePreferencesStore(io.File(root.settingsFile));
  final prefs = await SharedPreferences.getInstance();
  // #191: the chosen language before the first frame; System is Windows'.
  await showLanguage(
    AppLanguage.of(SharedPreferencesAppPreferences(prefs))
        .resolve(io.Platform.localeName.split(RegExp('[_-]')).first.toLowerCase()),
  );
  // Started by GargosyUpdate.exe: clean up after the update, or say why it failed.
  final updateOutcome = await appUpdaterFor(
    PlatformInfo.current,
    root: root,
    pid: io.pid,
    args: args,
    currentVersion: AppConstants.version,
  ).afterStart(args);
  await WindowService.init(
    fullscreen: WindowService.shouldStartFullscreen(args, prefs.getBool(WindowService.launchFullscreenPrefKey)),
  );
  runApp(
    ProviderScope(
      overrides: [
        appRootProvider.overrideWithValue(root),
        appPreferencesProvider.overrideWithValue(SharedPreferencesAppPreferences(prefs)),
        launchArgsProvider.overrideWithValue(args),
        updateOutcomeProvider.overrideWithValue(updateOutcome),
      ],
      child: const GargosyApp(),
    ),
  );
}

/// The log in `userdata\app\logs\` (issue #1): every `debugPrint`, redacted,
/// and every uncaught error, from here on. A folder that can't be written
/// means no file log, never a failed start.
void startFileLog(AppRoot root) {
  final sink = FileLogSink.open(PathGuard(root).check(root.logs));
  LoggerService.init(sink: sink, tag: () => LoggerService.profileTag);
  LoggerService.writeRaw('Gargosy ${AppConstants.version}');
  LoggerService.writeRaw('Windows ${io.Platform.operatingSystemVersion}');
  LoggerService.writeRaw('Folder ${root.root}');
  LoggerService.writeRaw('Started ${DateTime.now().toIso8601String()}');
  LoggerService.writeRaw('');
  final flutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    LoggerService().error(details.exception, details.stack, context: details.context?.toString());
    flutterError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    LoggerService().error(error, stack, context: 'Uncaught');
    return false;
  };
}
