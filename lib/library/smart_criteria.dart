import '../core/romm/romm_library_api.dart';
import '../l10n/tr.dart';

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

/// A smart collection's [criteria] in words, for its page: what it picks,
/// then its order (`Search “mario” · SNES · Racing · Sorted by Name, A–Z`).
/// [platformNames] by id; a key Gargosy doesn't know is said as RomM names it.
String describeCriteria(Map<String, dynamic> criteria, {Map<int, String> platformNames = const {}}) {
  String list(Object? v) => v is List ? v.join(', ') : '$v';
  final parts = <String>[];
  for (final e in criteria.entries) {
    final key = e.key;
    final value = e.value;
    if (value == null || value == '' || (value is List && value.isEmpty)) continue;
    switch (key) {
      case 'order_by' || 'order_dir':
        continue;
      case 'search_term':
        parts.add(tr('Search “{0}”', [value]));
      case 'platform_ids' || 'platform_id':
        parts.add(
          [
            for (final id in (value is List ? value : [value])) platformNames[id] ?? tr('Platform {0}', [id]),
          ].join(', '),
        );
      case 'favorite' when value == true:
        parts.add(tr('♥ Favourites'));
      case 'collection_id':
        parts.add(tr('In collection {0}', [value]));
      case 'genres' || 'regions':
        parts.add(list(value));
      default:
        final name = key.replaceAll('_', ' ');
        final label = name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
        parts.add(
          value == true
              ? label
              : value == false
              ? tr('Not {0}', [name])
              : '$label: ${list(value)}',
        );
    }
  }
  final by = criteria['order_by'];
  if (by is String && by.isNotEmpty) {
    final sort = GallerySort.values.firstWhere(
      (s) => s.field == by && s.group != SortGroup.thisPc,
      orElse: () => GallerySort.name,
    );
    final label = sort.field == by ? sort.label : by.replaceAll('_', ' ');
    final desc = criteria['order_dir'] == 'desc';
    final dir = by == 'name' ? (desc ? tr('Z–A') : tr('A–Z')) : (desc ? tr('descending') : tr('ascending'));
    parts.add(tr('Sorted by {0}, {1}', [label, dir]));
  }
  return parts.join(' · ');
}
