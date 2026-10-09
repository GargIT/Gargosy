import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/strategies/dolphin_strategy.dart';
import 'package:gargosy/core/emulator/strategies/pcsx2_strategy.dart';
import 'package:gargosy/core/emulator/strategies/ppsspp_strategy.dart';
import 'package:gargosy/core/emulator/strategies/retroarch_strategy.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/retroachievements/retroachievements_emulator_login.dart';
import 'package:gargosy/emulators/profile_directories.dart';
import 'package:gargosy/emulators/profile_launch_config.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/path_guard.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:path/path.dart' as p;

import '../helpers/game_fixtures.dart';
import '../helpers/profile_test_env.dart';

void main() {
  late AppRoot root;
  late io.Directory pc; // stands in for the PC's own user folders
  setUp(() async {
    root = await tempAppRoot();
    pc = await io.Directory.systemTemp.createTemp('real_user');
  });
  tearDown(() async {
    await io.Directory(root.root).delete(recursive: true);
    await pc.delete(recursive: true);
  });

  const login = RetroAchievementsEmulatorLogin(username: 'anna', token: 'tok', hardcore: false);

  test("in a profile, the copied emulator code never writes the RA login into the PC's own emulator settings", () async {
    final env = {'USERPROFILE': pc.path, 'APPDATA': p.join(pc.path, 'AppData')};
    final files = [
      io.File(p.join(pc.path, 'Documents', 'PCSX2', 'inis', 'PCSX2.ini')),
      io.File(p.join(pc.path, 'Documents', 'Dolphin Emulator', 'Config', 'Dolphin.ini')),
      io.File(p.join(pc.path, 'Documents', 'PPSSPP', 'PSP', 'SYSTEM', 'ppsspp.ini')),
    ];
    for (final f in files) {
      f
        ..createSync(recursive: true)
        ..writeAsStringSync('[General]\n');
    }
    final dirs = ProfileLaunchDirectories(root: root, paths: ProfilePaths(root, 'aaa'), prefs: MemoryPrefs());
    final platform = PlatformInfo('windows', environment: env);
    final g = game(1, 'G');
    await Pcsx2Strategy(dirs, platform: platform, raLoginLoader: () async => login).preLaunch(g, 'x.chd');
    await DolphinStrategy(dirs, platform: platform, raLoginLoader: () async => login).preLaunch(g, 'x.iso');
    await PPSSPPStrategy(dirs, platform: platform, raLoginLoader: () async => login).preLaunch(g, 'x.iso');
    for (final f in files) {
      expect(f.readAsStringSync(), '[General]\n', reason: f.path);
    }
  });

  LaunchContext ctx({RetroAchievementsEmulatorLogin? ra}) {
    final paths = ProfilePaths(root, 'aaa');
    final exeDir = p.join(root.emulators, 'pcsx2');
    io.Directory(exeDir).createSync(recursive: true);
    return LaunchContext(
      data: paths.emulatorDir('pcsx2'),
      exeDir: exeDir,
      bios: root.bios,
      profileId: 'aaa',
      profilesDir: root.profiles,
      guard: PathGuard(root, activeProfileId: 'aaa'),
      raLogin: ra,
    );
  }

  test("PCSX2 signs in with the profile's RA login, in the profile's own settings", () async {
    final c = ctx(ra: login);
    await ProfileLaunchConfig.of('pcsx2')!.prepare(c);
    final inis = p.join(c.data, 'PCSX2', 'inis');
    final ini = io.File(p.join(inis, 'PCSX2.ini')).readAsStringSync();
    expect(ini, contains('Enabled = true'));
    expect(ini, contains('Username = anna'));
    expect(ini, contains('ChallengeMode = false'));
    expect(io.File(p.join(inis, 'secrets.ini')).readAsStringSync(), contains('Token = tok'));
  });

  test("without an RA login PCSX2's own achievements settings are left alone", () async {
    final c = ctx();
    final ini = io.File(p.join(c.data, 'PCSX2', 'inis', 'PCSX2.ini'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[UI]\nSettingsVersion = 1\n[Achievements]\nEnabled = true\nUsername = bob\n');
    await ProfileLaunchConfig.of('pcsx2')!.prepare(c);
    expect(ini.readAsStringSync(), contains('Username = bob'));
  });

  test("RetroArch signs in from the profile's own config, which it may still save on exit", () async {
    final paths = ProfilePaths(root, 'aaa');
    final exeDir = p.join(root.emulators, 'retroarch');
    io.Directory(exeDir).createSync(recursive: true);
    final c = LaunchContext(
      data: paths.emulatorDir('retroarch'),
      exeDir: exeDir,
      bios: root.bios,
      profileId: 'aaa',
      profilesDir: root.profiles,
      guard: PathGuard(root, activeProfileId: 'aaa'),
      raLogin: login,
    );
    expect(await ProfileLaunchConfig.of('retroarch')!.prepare(c), ['--config=${p.join(c.data, 'retroarch.cfg')}']);
    final cfg = io.File(p.join(c.data, 'retroarch.cfg')).readAsStringSync();
    expect(cfg, contains('cheevos_enable = "true"'));
    expect(cfg, contains('cheevos_username = "anna"'));
    expect(cfg, contains('cheevos_token = "tok"'));
    expect(cfg, contains('cheevos_password = ""'));
    expect(cfg, contains('cheevos_hardcore_mode_enable = "false"'));
    expect(cfg, contains('config_save_on_exit = "true"'));
  });

  test("in a profile, RetroArch gets no separate login file with the token", () async {
    final dirs = ProfileLaunchDirectories(root: root, paths: ProfilePaths(root, 'aaa'), prefs: MemoryPrefs());
    final ra = RetroArchStrategy(dirs, platform: const PlatformInfo('windows'), raLoginLoader: () async => login);
    expect(await ra.retroAchievementsLaunchArgs(), isEmpty);
  });

  test("disconnecting takes the login out of the profile's RetroArch and PCSX2 settings", () async {
    final dirs = ProfileLaunchDirectories(root: root, paths: ProfilePaths(root, 'aaa'), prefs: MemoryPrefs());
    final cfg = io.File(p.join(dirs.dataDir('retroarch'), 'retroarch.cfg'))
      ..createSync(recursive: true)
      ..writeAsStringSync('cheevos_enable = "true"\ncheevos_username = "anna"\ncheevos_token = "tok"\n');
    final inis = p.join(dirs.dataDir('pcsx2'), 'PCSX2', 'inis');
    final secrets = io.File(p.join(inis, 'secrets.ini'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[Achievements]\nToken = tok\n');
    io.File(p.join(inis, 'PCSX2.ini')).writeAsStringSync('[Achievements]\nEnabled = true\nUsername = anna\n');
    dirs.signOutRetroAchievements();
    expect(cfg.readAsStringSync(), contains('cheevos_token = ""'));
    expect(cfg.readAsStringSync(), contains('cheevos_enable = "false"'));
    expect(secrets.readAsStringSync(), isNot(contains('= tok')));
    expect(io.File(p.join(inis, 'PCSX2.ini')).readAsStringSync(), isNot(contains('anna')));
  });
}
