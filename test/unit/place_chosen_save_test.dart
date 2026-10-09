import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/save/catalog/play_request.dart';
import 'package:gargosy/core/save/catalog/save_entry.dart';
import 'package:gargosy/core/save/catalog/save_maker.dart';
import 'package:gargosy/play/pre_launch_pull.dart';

void main() {
  const pcsx2 = SaveMaker('pcsx2');
  final romm = SaveEntry(source: SaveSource.romm, fileName: 'b.ps2', savedAt: DateTime(2026), maker: pcsx2, rommSave: const {'id': 4});
  final backup = SaveEntry(source: SaveSource.backup, fileName: 'b.zip', savedAt: DateTime(2026), maker: pcsx2);

  Future<List<String>> run(PlayRequest r) async {
    final steps = <String>[];
    await placeChosenSave(
      r,
      putInPlace: (save) async => steps.add('put ${save.fileName}'),
      confirmRommCopy: (save) async => steps.add('confirm ${save['id']}'),
      markSynced: () async => steps.add('synced'),
    );
    return steps;
  }

  test('a RomM save is put in place and marked synced', () async {
    expect(await run(PlayRequest(emulator: pcsx2, save: romm)), ['put b.ps2', 'synced']);
  });

  test('a backup is put in place but not marked synced (RomM does not have it)', () async {
    expect(await run(PlayRequest(emulator: pcsx2, save: backup)), ['put b.zip']);
  });

  test("this PC's own save is left as it is; RomM is told when it has a copy", () async {
    expect(await run(const PlayRequest(emulator: pcsx2)), isEmpty);
    expect(await run(const PlayRequest(emulator: pcsx2, rommCopy: {'id': 9})), ['confirm 9']);
  });
}
