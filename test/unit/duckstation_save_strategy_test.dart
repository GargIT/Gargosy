// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy: lints the newer SDK raises on copied code, kept as upstream.
// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/duckstation_save_strategy.dart';
import 'package:gargosy/core/storage/app_preferences.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/core/storage/shared_preferences_app_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal DirectoryService stub — implements only the methods
/// DuckstationSaveStrategy calls during save resolution.
class _StubDirectoryService extends DirectoryService {
  final AppPreferences testPrefs;
  final String? _exePath;
  final String _appSupport;

  _StubDirectoryService._internal(this.testPrefs, {required String? exePath, required String appSupport})
    : _exePath = exePath,
      _appSupport = appSupport,
      super(testPrefs);

  static Future<_StubDirectoryService> create({String? exePath, String appSupport = ''}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferencesAppPreferences(await SharedPreferences.getInstance());
    return _StubDirectoryService._internal(prefs, exePath: exePath, appSupport: appSupport);
  }

  @override
  Future<String?> findEmulatorExecutable(String emulatorId, String executableName) async => _exePath;

  @override
  Future<String> getEmulatorAppSupportDirectory(String emulatorName, {String? platformSlug}) async => _appSupport;
}

void main() {
  group('DuckstationSaveStrategy portable mode via settings.ini (scoop)', () {
    test('treats install as portable when settings.ini sits next to exe', () async {
      final base = await Directory.systemTemp.createTemp('duckstation_scoop');
      try {
        final exeDir = p.join(base.path, 'duckstation');
        await Directory(p.join(exeDir, 'memcards')).create(recursive: true);
        await Directory(p.join(exeDir, 'savestates')).create(recursive: true);
        // Scoop/portable builds have settings.ini but NOT portable.txt.
        await File(p.join(exeDir, 'settings.ini')).writeAsString('[Core]\n');
        final fakeExe = p.join(exeDir, 'duckstation-qt-x64-ReleaseLTCG.exe');
        await File(fakeExe).writeAsString('');

        // LocalAppData is empty — only the exe-dir (portable) layout has data.
        final emptyLocal = p.join(base.path, 'empty');
        final ds = await _StubDirectoryService.create(exePath: fakeExe, appSupport: '/nonexistent');
        final strategy = DuckstationSaveStrategy(
          ds,
          ds.testPrefs,
          platform: PlatformInfo('windows', environment: {'LOCALAPPDATA': emptyLocal}),
        );

        // The cards are sigil's (#57); the states' folder is found the same way.
        final states = await strategy.stateDirectory(
          Game(id: 'g_scoop', name: 'Suikoden II.bin', platformSlug: 'ps1', fileSize: 0),
          '/roms/ps1/Suikoden II.bin',
        );
        expect(states, p.join(exeDir, 'savestates'), reason: 'settings.ini next to exe should trigger portable mode');
      } finally {
        await base.delete(recursive: true);
      }
    });
  });

  group('SaveStrategy.normalizeSaveMatchName', () {
    test('strips region/version tags and collapses whitespace', () async {
      final ds = await _StubDirectoryService.create(exePath: null, appSupport: '');
      final strategy = DuckstationSaveStrategy(
        ds,
        ds.testPrefs,
        platform: const PlatformInfo('linux', environment: {'HOME': ''}),
      );

      expect(strategy.normalizeSaveMatchName('Final Fantasy VII (USA)'), 'Final Fantasy VII');
      expect(strategy.normalizeSaveMatchName('Suikoden II [Rev 1]'), 'Suikoden II');
      expect(strategy.normalizeSaveMatchName('Game (USA) (En,Fr)'), 'Game');
      expect(strategy.normalizeSaveMatchName('  spaced   name  '), 'spaced name');
      expect(strategy.normalizeSaveMatchName('Trailing---'), 'Trailing');
    });
  });
}
