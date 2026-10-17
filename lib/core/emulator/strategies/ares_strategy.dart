// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:gargosy/core/emulator/emulator_strategy.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/strategies/ares_save_strategy.dart';
import 'package:gargosy/core/storage/directory_service.dart';
import 'package:gargosy/core/emulator/platform_slugs.dart';

/// Maps Gargosy platform slugs to Ares --system full display names.
/// Source: mia.cpp media[] vector + mia/medium/*.cpp name() overrides.
const Map<String, String> kAresSystemNames = {
  'atari2600':       'Atari 2600',
  'nes':             'Famicom',
  'famicom':         'Famicom',
  'snes':            'Super Famicom',
  'sfc':             'Super Famicom',
  'n64':             'Nintendo 64',
  'gb':              'Game Boy',
  'gbc':             'Game Boy Color',
  'gba':             'Game Boy Advance',
  'game-boy':        'Game Boy',
  'game-boy-color':  'Game Boy Color',
  'game-boy-advance':'Game Boy Advance',
  'gamegear':        'Game Gear',
  'sms':             'Master System',
  'mastersystem':    'Master System',
  'genesis':         'Mega Drive',
  'megadrive':       'Mega Drive',
  'md':              'Mega Drive',
  'segacd':          'Mega CD',
  'psx':             'PlayStation',
  'ps1':             'PlayStation',
  'playstation':     'PlayStation',
  'pce':             'PC Engine',
  'pcengine':        'PC Engine',
  'neogeo':          'Neo Geo',
  'neo-geo':         'Neo Geo',
  'neogeoaes':       'Neo Geo',
  'neogeomvs':       'Neo Geo',
  'neo-geo-aes':     'Neo Geo',
  'neo-geo-mvs':     'Neo Geo',
  'mvs':             'Neo Geo',
  'aes':             'Neo Geo',
  'msx':             'MSX',
  'coleco':          'ColecoVision',
  'colecovision':    'ColecoVision',
  'zxspectrum':      'ZX Spectrum',
  'zx-spectrum':     'ZX Spectrum',
  'wonderswan':      'WonderSwan',
  'wonderswancolor': 'WonderSwan Color',
  'ngp':             'Neo Geo Pocket',
  'ngpc':            'Neo Geo Pocket Color',
  'neo-geo-pocket':  'Neo Geo Pocket',
};

class AresStrategy extends EmulatorStrategy {
  final DirectoryService _directoryService;

  AresStrategy(this._directoryService, {super.platform});

  @override
  DirectoryService get directoryService => _directoryService;

  @override
  String get name => 'Ares';

  @override
  String get emulatorId => 'ares';

  @override
  List<String> get supportedSlugs => kAresSystemNames.keys.toList();

  @override
  String get windowsExecutable => 'ares.exe';

  @override
  String get linuxExecutable => 'ares.AppImage';

  @override
  String get macosExecutable => 'ares.app/Contents/MacOS/ares';

  @override
  bool get supportsSaveSync => true;

  /// Gargosy (#66): states sync through RomM (AresSaveStrategy).
  @override
  bool get supportsStateSync => true;

  @override
  bool get supportsStateLoadOnLaunch => true;

  /// ares: `--save-state <slot>` (1-9) loads that slot once the game starts
  /// (desktop-ui/desktop-ui.cpp); the state is in place under its slot's name.
  @override
  List<String> stateLoadArgs(String statePath) => ['--save-state', '${AresSaveStrategy.stateSlot(p.basename(statePath)) ?? 1}'];

  @override
  bool canLoadState(String fileName) => AresSaveStrategy.stateSlot(fileName) != null;

  /// Returns the Ares --system flag for a given Gargosy platform slug.
  String? getSystemNameForSlug(String? slug) {
    if (slug == null) return null;
    return kAresSystemNames[canonicalPlatformSlug(slug.toLowerCase())];
  }

  /// Builds the full argument list for launching a specific game.
  /// Format: `ares --system <name> "<rompath>"`
  List<String> _buildArgs(String systemName) {
    return ['--system', systemName];
  }

  /// [launch] and [launchWithHandle] come here through the base class.
  /// Gargosy (#66): the ExtraArgs variants are overridden, not [launch], so a
  /// Resume's `--save-state` reaches ares with `--system`.
  @override
  Future<void> launchWithExtraArgs(Game game, String romPath, {List<String> extraArgs = const []}) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    final systemName = getSystemNameForSlug(game.platformSlug);
    if (systemName == null) {
      throw Exception('Ares does not support platform: ${game.platformSlug}');
    }

    final normalizedRomPath = p.absolute(p.normalize(romPath));
    final args = [..._buildArgs(systemName), ...extraArgs];
    await preLaunch(game, romPath);
    await directoryService.launchGame(game, normalizedRomPath, emulatorId, exePath, args: args);
    await postLaunch(game, romPath);
  }

  @override
  Future<Process?> launchWithHandleAndExtraArgs(Game game, String romPath, {List<String> extraArgs = const []}) async {
    final exePath = await findExecutable();
    if (exePath == null) throw Exception('$name not found. Please download it first.');

    final systemName = getSystemNameForSlug(game.platformSlug);
    if (systemName == null) {
      throw Exception('Ares does not support platform: ${game.platformSlug}');
    }

    final normalizedRomPath = p.absolute(p.normalize(romPath));
    final args = [..._buildArgs(systemName), ...extraArgs];
    await preLaunch(game, romPath);
    final process = await directoryService.launchGameWithHandle(game, normalizedRomPath, emulatorId, exePath, args: args);
    await process?.exitCode;
    await postLaunch(game, romPath);
    return process;
  }

  /// Gives ares a saves folder before it starts, when it has none, so it
  /// keeps saves there and not next to the ROMs (see AresSaveStrategy).
  @override
  Future<void> preLaunch(Game game, String romPath) async {
    await AresSaveStrategy(_directoryService, platform: platform).ensureSavesPath();
  }

  @override
  String resolveSavePath(Game game) => '';
}
