import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/game_versions.dart';

import '../helpers/game_fixtures.dart';

Game _g(int id, String name, {List<int> siblings = const [], List<String> regions = const []}) => Game.fromJson({
  ...gameJson(id, name, fsName: '$name.chd'),
  'regions': regions,
  'sibling_roms': [
    for (final s in siblings) {'id': s, 'name': name, 'fs_name_no_ext': '$name ($s)', 'is_main_sibling': false},
  ],
});

void main() {
  test("RomM's regions as three-letter badges; an unknown name by its first letters; Unknown left out", () {
    expect(
      [
        for (final r in ['USA', 'Europe', 'Japan', 'World', 'England', 'Germany', 'Atlantis']) regionBadge(r),
      ],
      ['USA', 'EUR', 'JPN', 'WLD', 'UK', 'GER', 'ATL'],
    );
    expect(regionBadge('Unknown'), isNull);
    expect(regionBadges(['Holland', 'Netherlands', 'USA', 'Unknown']), ['NLD', 'USA']);
  });

  test("a version is told by its file name's tags", () {
    expect(versionLabel('Ico', 'Ico (USA) (Rev 1)'), '(USA) (Rev 1)');
    expect(versionLabel('Ico', 'Ico [b]'), '[b]');
    expect(versionLabel('Ico', 'Ico'), 'Ico');
    expect(versionLabel('Ico', ''), 'Ico');
  });

  test("RomM's sibling_roms are read, counted and kept through the snapshot", () {
    final g = Game.fromJson({
      ...gameJson(1, 'Ico', fsName: 'Ico (USA).chd'),
      'sibling_roms': [
        {'id': 2, 'name': 'Ico', 'fs_name_no_ext': 'Ico (Europe)', 'is_main_sibling': false},
      ],
    });
    expect(versionCount(g), 2);
    expect([for (final v in allVersions(g)) versionLabel(v.name, v.fsNameNoExt)], ['(USA)', '(Europe)']);
    final back = Game.fromJson(g.toJson());
    expect(back.siblings.single.id, '2');
    expect(back.siblings.single.fsNameNoExt, 'Ico (Europe)');
    expect(versionCount(game(3, 'Rez')), 1);
  });

  test('On this PC folds as RomM: of the versions only the first in the order stays', () {
    final list = foldVersions([
      _g(1, 'Ico', siblings: [2]),
      _g(3, 'Rez'),
      _g(2, 'Ico', siblings: [1]),
    ]);
    expect([for (final g in list) g.id], ['1', '3']);
  });

  test('RomM folds versions when asked', () {
    expect(const GalleryQuery().toParams(offset: 0, limit: 1).containsKey('group_by_meta_id'), isFalse);
    expect(const GalleryQuery().toParams(offset: 0, limit: 1, foldVersions: true)['group_by_meta_id'], true);
  });
}
