// Adapted from Freegosy (MIT, © 2026 abduznik).
// Gargosy (#57): PCSX2's cards sync through sigil; what's left of its
// strategy here is when a pull must finish before launch. The push and pull
// tests went with that code.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/formats/ps2_memory_card.dart';
import 'package:path/path.dart' as p;

import '../helpers/pcsx2_test_env.dart';

/// PCSX2 opens a file card (`memcards/Mcd001.ps2`, an 8 MB image shared by
/// every game) when a game starts, so a pull onto one must finish first; a
/// folder card needs no wait.
void main() {
  late Directory tempDir;
  late Pcsx2TestEnv env;
  late String memcards;
  final game = Game(id: '77', name: 'Ace Combat 5', platformSlug: 'ps2', fileSize: 0);
  String romPath() => p.join(tempDir.path, 'roms', 'Ace Combat 5 (SLUS-20851).iso');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pcsx2_file_cards_');
    env = await Pcsx2TestEnv.create(tempDir);
    memcards = p.join(env.exeDir, 'memcards');
  });

  tearDown(() => tempDir.delete(recursive: true));

  test('a file card: the pull finishes before PCSX2 starts', () async {
    File(p.join(memcards, 'Mcd001.ps2')).writeAsBytesSync(Ps2MemoryCard.formatted(now: DateTime.utc(2026)));
    expect(await env.strategy.pullMustFinishBeforeLaunch(game, romPath()), isTrue);
  });

  test('a folder card: no wait before launch', () async {
    final folderCard = Directory(p.join(memcards, 'Mcd001.ps2'))..createSync();
    File(p.join(folderCard.path, '_pcsx2_superblock')).writeAsBytesSync(Uint8List(8192));
    expect(await env.strategy.pullMustFinishBeforeLaunch(game, romPath()), isFalse);
  });
}
