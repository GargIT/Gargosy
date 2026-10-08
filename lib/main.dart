import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'app.dart';
import 'core/platform/window_service.dart';
import 'core/storage/gargosy_path_provider.dart';
import 'core/storage/json_file_preferences_store.dart';
import 'core/storage/shared_preferences_app_preferences.dart';
import 'profiles/app_root.dart';
import 'profiles/profile_providers.dart';
import 'ui/screens/startup_error_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = AppRoot.fromArgs(args, io.Platform.resolvedExecutable);
  try {
    await root.ensureLayout();
  } on io.FileSystemException catch (e) {
    runApp(StartupErrorApp(message: '${e.message}: ${e.path ?? root.root}'));
    return;
  }
  // Portable: plugins and settings stay in userdata\, never AppData (spec §3).
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
