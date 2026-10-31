import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/download_all.dart';

import '../helpers/fake_library_api.dart';
import '../helpers/game_fixtures.dart';

void main() {
  test("every game of the gallery, page after page, in its order, without those it skips", () async {
    final api = FakeLibraryApi([for (var i = 1; i <= 7; i++) game(i, 'G$i')]);
    final got = await gamesToDownload(api, const GalleryQuery(platformId: 1), skip: (g) => g.id == '2', pageSize: 3);
    expect([for (final g in got) g.id], ['1', '3', '4', '5', '6', '7']);
    expect([for (final q in api.queries) q.$2], [0, 3, 6], reason: 'three pages of three');
    expect(api.folded, everyElement(isTrue), reason: 'versions folded, as the gallery shows them');
  });

  test('a game with another version on this PC or queued is left out; versions fold', () async {
    Game withSibling(int id, int other) => Game.fromJson({
      ...gameJson(id, 'G$id'),
      'sibling_roms': [
        {'id': other, 'name': 'G$other', 'fs_name_no_ext': 'G$other (Rev 1)'},
      ],
    });
    final api = FakeLibraryApi([withSibling(1, 2), withSibling(2, 1), game(3, 'G3')]);
    final got = await gamesToDownload(api, const GalleryQuery(), skip: (_) => false, have: {'2'});
    expect([for (final g in got) g.id], ['3']);
    final all = await gamesToDownload(api, const GalleryQuery(), skip: (_) => false);
    expect([for (final g in all) g.id], ['1', '3'], reason: 'one card per game, as the gallery shows');
  });

  test('the size is RomM\'s sizes added up', () {
    Game sized(int id, int bytes) => Game.fromJson(gameJson(id, 'G$id', size: bytes));
    expect(sizeOf([sized(1, 10), sized(2, 32)]), 42);
  });
}
