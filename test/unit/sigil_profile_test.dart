import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/core/save/save_strategy.dart';
import 'package:gargosy/profiles/app_root.dart';
import 'package:gargosy/profiles/profile_paths.dart';
import 'package:gargosy/sigil/sigil_library.dart';
import 'package:gargosy/sigil/sigil_profile.dart';
import 'package:gargosy/sigil/sigil_save_strategy.dart';
import 'package:path/path.dart' as p;

class _Old extends SaveStrategy {
  @override
  String get strategyId => 'old';
  @override
  Future<String?> getSaveDir(Game game, String romPath) async => null;
  @override
  Future<List<io.File>> getSaveFiles(
    Game game,
    String romPath, {
    DateTime? sessionStart,
    String syncMode = 'both',
  }) async => [];
  @override
  Future<bool> restoreSave(Game game, String destPath, Uint8List data, String filename) async => false;
}

void main() {
  final paths = ProfilePaths(AppRoot(r'C:\gargosy-test'), 'aaa');

  test("the profile's sigil strategies: the six emulators, their folders and sigil's files inside the profile", () {
    final wrap = sigilSavesFor(paths)!;
    final pcsx2 = wrap('pcsx2', _Old()) as SigilSaveStrategy;
    expect(pcsx2.emulatorDir(), paths.emulatorDir('pcsx2'));
    expect(pcsx2.states.dir, p.join(paths.dir, 'sigil'));
    expect(p.isWithin(paths.dir, pcsx2.unitsDir), isTrue);
    for (final id in ['duckstation', 'dolphin', 'ppsspp', 'mgba']) {
      expect(wrap(id, _Old()), isA<SigilSaveStrategy>(), reason: id);
    }
    expect(wrap('flycast', null), isA<SigilSaveStrategy>());
    final old = _Old();
    expect(wrap('retroarch', old), same(old));
  });

  test("without a usable sigil.dll the old strategies stay (and it says why in the log)", () {
    final was = SigilLibrary.path;
    addTearDown(() => SigilLibrary.path = was);
    SigilLibrary.path = r'C:\nowhere\sigil.dll';
    expect(sigilSavesFor(paths), isNull);
  });
}
