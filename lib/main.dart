import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/platform/window_service.dart';
import 'core/save/backup_entry.dart';
import 'core/storage/gargosy_path_provider.dart';
import 'core/storage/json_file_preferences_store.dart';
import 'core/storage/shared_preferences_app_preferences.dart';
import 'profiles/app_root.dart';
import 'profiles/portable_temp.dart';
import 'profiles/profile_providers.dart';
import 'ui/screens/startup_error_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Backups' index: one Hive box per profile, in the profile's folder.
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(BackupEntryAdapter());
  // The version from pubspec.yaml: shown in the user menu, sent to RomM and RetroAchievements.
  await AppConstants.init();
  final root = AppRoot.fromArgs(args, io.Platform.resolvedExecutable);
  try {
    await root.ensureLayout();
  } on io.FileSystemException catch (e) {
    runApp(StartupErrorApp(message: '${e.message}: ${e.path ?? root.root}'));
    return;
  }
  // Portable: plugins, settings and temp files stay in userdata\, never
  // AppData (spec §3).
  usePortableTemp(p.join(root.appData, 'temp'));
  PathProviderPlatform.instance = GargosyPathProvider(appDataDir: root.appData, previous: PathProviderPlatform.instance);
  SharedPreferencesStorePlatform.instance = JsonFilePreferencesStore(io.File(root.settingsFile));
  final prefs = await SharedPreferences.getInstance();
  await WindowService.init(
      fullscreen: WindowService.shouldStartFullscreen(args, prefs.getBool(WindowService.launchFullscreenPrefKey)));
  runApp(ProviderScope(
    overrides: [
      appRootProvider.overrideWithValue(root),
      appPreferencesProvider.overrideWithValue(SharedPreferencesAppPreferences(prefs)),
    ],
    child: const GargosyApp(),
  ));
}
