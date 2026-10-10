// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:gargosy/core/emulator/strategies/scummvm_strategy.dart';
import 'package:gargosy/core/platform/platform_info.dart';
import 'package:gargosy/core/romm/romm_models.dart';

import 'strategy_registry_test.mocks.dart';

void main() {
  late Directory tmp;
  late Directory gameDir;
  late MockDirectoryService dirService;
  final game = Game(id: '7', name: 'Drascula', platformSlug: 'scummvm', fileSize: 0);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('scummvm_launch');
    gameDir = Directory(p.join(tmp.path, 'games', 'Drascula The Vampire'));
    await gameDir.create(recursive: true);
    await File(p.join(gameDir.path, 'packet.001')).writeAsString('data');
    dirService = MockDirectoryService();
  });

  tearDown(() => tmp.delete(recursive: true));

  test('throws a clear error when ScummVM is not installed', () async {
    when(dirService.findEmulatorExecutable('scummvm', any)).thenAnswer((_) async => null);
    // Windows: no distro-package fallback, so nothing is found.
    final strategy = ScummVMStrategy(dirService, platform: const PlatformInfo('windows'));

    expect(await strategy.findExecutable(), isNull);
    await expectLater(strategy.launchWithHandle(game, gameDir.path),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('ScummVM not found'))));
  });

  test('looks up scummvm.exe', () async {
    when(dirService.findEmulatorExecutable(any, any)).thenAnswer((_) async => null);
    await ScummVMStrategy(dirService, platform: const PlatformInfo('windows')).findExecutable();
    verify(dirService.findEmulatorExecutable('scummvm', 'scummvm.exe')).called(1);
  });
}
