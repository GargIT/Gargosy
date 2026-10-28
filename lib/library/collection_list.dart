import '../core/romm/romm_library_api.dart';
import '../l10n/tr.dart';

/// The Collections tab's Kind (#121): which kinds of collection it shows.
enum CollectionKindFilter {
  all('All'),
  regular('Collections'),
  smart('Smart'),
  virtual('Virtual');

  const CollectionKindFilter(this._label);
  final String _label;

  /// In the shown language (#191).
  String get label => tr(_label);

  bool shows(CollectionKind kind) => switch (this) {
    all => true,
    regular => kind == CollectionKind.regular,
    smart => kind == CollectionKind.smart,
    virtual => kind == CollectionKind.virtual,
  };
}

/// Whose collections the tab shows. Virtual ones are no one's.
enum CollectionWhose {
  everyone('Everyone\'s'),
  mine('Mine'),
  others('Others\'');

  const CollectionWhose(this._label);
  final String _label;

  /// In the shown language (#191).
  String get label => tr(_label);
}

enum CollectionSort {
  name('Name'),
  games('Games'),
  updated('Recently updated');

  const CollectionSort(this._label);
  final String _label;

  /// In the shown language (#191).
  String get label => tr(_label);
}

/// The players' collections (regular and smart) the tab shows: the user's
/// own favourites first (another player's are left out), then the rest in
/// [sort] order, those matching [filter] (part of the name), [kind] and
/// [whose] only.
List<RommCollection> curatedCollections(
  List<RommCollection> regular,
  List<RommCollection> smart, {
  required int? userId,
  String filter = '',
  CollectionKindFilter kind = CollectionKindFilter.all,
  CollectionWhose whose = CollectionWhose.everyone,
  CollectionSort sort = CollectionSort.name,
}) {
  final term = filter.trim().toLowerCase();
  bool mine(RommCollection c) => userId == null || c.userId == userId;
  bool keep(RommCollection c) =>
      kind.shows(c.kind) &&
      (term.isEmpty || c.name.toLowerCase().contains(term) || (c.isFavorite && 'favourites'.contains(term))) &&
      switch (whose) {
        CollectionWhose.everyone => true,
        CollectionWhose.mine => mine(c),
        CollectionWhose.others => !mine(c),
      };
  final favourites = regular.where((c) => c.isFavorite && mine(c) && keep(c));
  final rest = [...regular.where((c) => !c.isFavorite), ...smart].where(keep).toList()..sort(_comparer(sort));
  return [...favourites, ...rest];
}

/// RomM's virtual collections the tab shows, by type in
/// [virtualCollectionTypes] order (a type with none left out), each in
/// [sort] order. None unless [kind] shows virtual ones and [whose] is
/// everyone's.
List<(String type, List<RommCollection> items)> virtualGroups(
  Map<String, List<RommCollection>> byType, {
  String filter = '',
  CollectionKindFilter kind = CollectionKindFilter.all,
  CollectionWhose whose = CollectionWhose.everyone,
  CollectionSort sort = CollectionSort.name,
}) {
  if (!kind.shows(CollectionKind.virtual) || whose != CollectionWhose.everyone) return const [];
  final term = filter.trim().toLowerCase();
  return [
    for (final type in virtualCollectionTypes.keys)
      if ([...?byType[type]?.where((c) => term.isEmpty || c.name.toLowerCase().contains(term))]..sort(_comparer(sort))
          case final items when items.isNotEmpty)
        (type, items),
  ];
}

int Function(RommCollection, RommCollection) _comparer(CollectionSort sort) {
  int byName(RommCollection a, RommCollection b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return switch (sort) {
    CollectionSort.name => byName,
    CollectionSort.games => (a, b) => b.romCount != a.romCount ? b.romCount.compareTo(a.romCount) : byName(a, b),
    CollectionSort.updated => (a, b) {
      final at = a.updatedAt, bt = b.updatedAt;
      if (at == bt) return byName(a, b);
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    },
  };
}

/// How many of [c]'s games are on this PC ([downloadedIds]: RomM ids).
int onThisPc(RommCollection c, Set<int> downloadedIds) => c.romIds.where(downloadedIds.contains).length;
