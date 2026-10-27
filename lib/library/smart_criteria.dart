import '../core/romm/romm_library_api.dart';

/// A gallery saved as a smart collection (#188): RomM's criteria, under the
/// names its `/api/roms` takes (a smart collection's `filter_criteria` is the
/// same vocabulary), and what was left out because RomM can't run it.
class SmartCriteria {
  const SmartCriteria(this.criteria, this.leftOut);

  final Map<String, dynamic> criteria;

  /// Gargosy's own filters, said to the player before saving.
  final List<String> leftOut;

  /// Whether the criteria pick anything narrower than the whole library.
  bool get picksSomething => criteria.keys.any((k) => k != 'order_by' && k != 'order_dir');
}

/// Whether [q]'s gallery can be saved as a smart collection: not one that is
/// a smart collection already (RomM drops a smart collection id from criteria).
bool canSaveAsSmart(GalleryQuery q) => q.smartCollectionId == null;

/// [q] as a smart collection's criteria; [thisPc]: On this PC was on.
SmartCriteria smartCriteriaOf(GalleryQuery q, {bool thisPc = false}) {
  final leftOut = [if (thisPc) 'On this PC', if (q.sort.group == SortGroup.thisPc) 'the Downloaded order'];
  // Best match needs a term and the Downloaded order is Gargosy's: by name.
  final byName = q.sort == GallerySort.bestMatch || q.sort.group == SortGroup.thisPc;
  final params = (byName ? q.copyWith(sort: GallerySort.name, descending: false) : q).toParams(offset: 0, limit: 0)
    ..removeWhere((k, _) => k == 'offset' || k == 'limit' || k.startsWith('with_') || k == 'smart_collection_id');
  return SmartCriteria(params, leftOut);
}
