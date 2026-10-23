import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/library/collection_list.dart';

void main() {
  const me = 7;
  final regular = [
    const RommCollection(id: 1, name: 'Favorites', isFavorite: true, userId: me, romCount: 3),
    const RommCollection(id: 9, name: 'Favorites', isFavorite: true, userId: 8, romCount: 40),
    RommCollection(id: 2, name: 'RPGs', userId: me, romCount: 12, updatedAt: DateTime(2026, 1, 1)),
    RommCollection(id: 3, name: 'arcade', userId: 8, romCount: 30, isPublic: true, updatedAt: DateTime(2026, 9, 1)),
  ];
  const smart = [RommCollection(id: 4, name: 'Never finished', kind: CollectionKind.smart, userId: me, romCount: 5)];
  List<String> names(List<RommCollection> l) => [for (final c in l) c.name];

  test("the user's favourites first (another player's left out), then the rest by name, smart ones too", () {
    expect(names(curatedCollections(regular, smart, userId: me)), ['Favorites', 'arcade', 'Never finished', 'RPGs']);
  });

  test('by games (most first) or recently updated (unknown last)', () {
    expect(names(curatedCollections(regular, smart, userId: me, sort: CollectionSort.games)), [
      'Favorites',
      'arcade',
      'RPGs',
      'Never finished',
    ]);
    expect(names(curatedCollections(regular, smart, userId: me, sort: CollectionSort.updated)), [
      'Favorites',
      'arcade',
      'RPGs',
      'Never finished',
    ]);
  });

  test('kind, whose and the filter narrow it; "fav" finds Favourites', () {
    expect(names(curatedCollections(regular, smart, userId: me, kind: CollectionKindFilter.smart)), ['Never finished']);
    expect(names(curatedCollections(regular, smart, userId: me, kind: CollectionKindFilter.virtual)), isEmpty);
    expect(names(curatedCollections(regular, smart, userId: me, whose: CollectionWhose.others)), ['arcade']);
    expect(names(curatedCollections(regular, smart, userId: me, whose: CollectionWhose.mine)), [
      'Favorites',
      'Never finished',
      'RPGs',
    ]);
    expect(names(curatedCollections(regular, smart, userId: me, filter: ' RP ')), ['RPGs']);
    expect(names(curatedCollections(regular, smart, userId: me, filter: 'fav')), ['Favorites']);
  });

  test('virtual ones by type in their order, empty types left out; none for Collections or Mine', () {
    const mario = RommCollection(id: 0, name: 'Mario', kind: CollectionKind.virtual, virtualType: 'franchise');
    const zelda = RommCollection(id: 0, name: 'Zelda', kind: CollectionKind.virtual, virtualType: 'franchise');
    const rpg = RommCollection(id: 0, name: 'Role-playing', kind: CollectionKind.virtual, virtualType: 'genre');
    final byType = {
      'genre': [rpg],
      'franchise': [zelda, mario],
      'company': <RommCollection>[],
    };
    final groups = virtualGroups(byType);
    expect(
      [for (final (t, items) in groups) '$t: ${names(items).join(', ')}'],
      ['franchise: Mario, Zelda', 'genre: Role-playing'],
    );
    expect(virtualGroups(byType, filter: 'zel').single.$2.single.name, 'Zelda');
    expect(virtualGroups(byType, kind: CollectionKindFilter.regular), isEmpty);
    expect(virtualGroups(byType, whose: CollectionWhose.mine), isEmpty);
  });

  test('how many of its games are on this PC', () {
    expect(onThisPc(const RommCollection(id: 1, name: 'x', romIds: {1, 2, 3}), {2, 3, 9}), 2);
  });
}
