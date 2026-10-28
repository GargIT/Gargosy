import 'package:gargosy/core/romm/romm_collection_edits.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';

/// The user's collections kept in [all]; every change is recorded in [calls].
class FakeCollectionEdits implements CollectionEdits {
  FakeCollectionEdits(this.all);

  final List<RommCollection> all;
  final calls = <String>[];

  RommCollection _swap(int id, RommCollection Function(RommCollection) change) {
    final i = all.indexWhere((c) => c.id == id);
    return all[i] = change(all[i]);
  }

  RommCollection _with(RommCollection c, {String? name, Set<int>? romIds, bool? isPublic}) => RommCollection(
    id: c.id,
    kind: c.kind,
    filterSummary: c.filterSummary,
    filterCriteria: c.filterCriteria,
    name: name ?? c.name,
    romIds: romIds ?? c.romIds,
    romCount: (romIds ?? c.romIds).length,
    isPublic: isPublic ?? c.isPublic,
    isFavorite: c.isFavorite,
    userId: c.userId,
  );

  @override
  Future<RommCollection> setIn(int collectionId, String gameId, bool inIt) async {
    calls.add('${inIt ? 'in' : 'out'} $collectionId $gameId');
    return _swap(collectionId, (c) {
      final ids = {...c.romIds};
      inIt ? ids.add(int.parse(gameId)) : ids.remove(int.parse(gameId));
      return _with(c, romIds: ids);
    });
  }

  @override
  Future<RommCollection> create(String name, {bool shared = false, String? gameId}) async {
    calls.add('create $name${shared ? ' shared' : ''}');
    final c = RommCollection(
      id: 100 + all.length,
      name: name,
      isPublic: shared,
      userId: 7,
      romIds: {?int.tryParse(gameId ?? '')},
    );
    all.add(c);
    return c;
  }

  @override
  Future<RommCollection> createSmart(String name, Map<String, dynamic> criteria, {bool shared = false}) async {
    calls.add('create smart $name${shared ? ' shared' : ''} $criteria');
    final c = RommCollection(id: 100 + all.length, name: name, kind: CollectionKind.smart, isPublic: shared, userId: 7);
    all.add(c);
    return c;
  }

  @override
  Future<RommCollection> rename(RommCollection c, String name) async {
    calls.add('rename ${c.id} $name');
    return _swap(c.id, (x) => _with(x, name: name));
  }

  @override
  Future<RommCollection> setShared(RommCollection c, bool shared) async {
    calls.add('share ${c.id} $shared');
    return _swap(c.id, (x) => _with(x, isPublic: shared));
  }

  @override
  Future<void> delete(RommCollection c) async {
    calls.add('delete ${c.id}');
    all.removeWhere((x) => x.id == c.id);
  }
}
