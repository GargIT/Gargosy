import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_library_api.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/recent_searches.dart';
import 'package:gargosy/ui/widgets/nothing_matches.dart';

import '../helpers/profile_test_env.dart';

void main() {
  group('RecentSearches (#132)', () {
    test('newest first, the same term once in any case, at most eight, kept in the prefs', () async {
      final prefs = MemoryPrefs();
      final recent = RecentSearches(prefs);
      for (var i = 0; i < 9; i++) {
        await recent.remember('game $i');
      }
      await recent.remember(' Game 3 ');
      expect(recent.state.first, 'Game 3');
      expect(recent.state.length, RecentSearches.max);
      expect(recent.state.where((t) => t.toLowerCase() == 'game 3').length, 1);
      expect(recent.state, isNot(contains('game 0')), reason: 'the oldest went');
      expect(RecentSearches(prefs).state, recent.state, reason: 'read back');
      await recent.forget('Game 3');
      expect(RecentSearches(prefs).state, isNot(contains('Game 3')));
      await recent.remember('   ');
      expect(recent.state.length, RecentSearches.max - 1);
    });

    test('a damaged value reads as none', () {
      final prefs = MemoryPrefs()..values[RecentSearches.key] = '{oops';
      expect(RecentSearches(prefs).state, isEmpty);
      prefs.values[RecentSearches.key] = '{"a": 1}';
      expect(RecentSearches(prefs).state, isEmpty);
    });
  });

  group('hiddenBy (#132)', () {
    Platform p(int id, String name) =>
        Platform.fromJson({'id': id, 'name': name, 'slug': 's$id', 'fs_slug': 's$id', 'display_name': name});

    test("names On this PC, a picked platform, genres and regions, not a platform page's own", () {
      const base = GalleryQuery();
      expect(hiddenBy(const GalleryQuery(search: 'x'), base, thisPc: false), isEmpty);
      final q = GalleryQuery(platformId: 4, genres: {'Racing'}, regions: {'USA', 'Europe'});
      expect(hiddenBy(q, base, thisPc: true, platforms: [p(4, 'Nintendo 64')]), [
        'On this PC',
        'the platform Nintendo 64',
        'the genre Racing',
        'the regions USA and Europe',
      ]);
      expect(hiddenBy(const GalleryQuery(platformId: 4), const GalleryQuery(platformId: 4), thisPc: false), isEmpty);
    });

    test('joinAnd', () {
      expect(joinAnd([]), '');
      expect(joinAnd(['a']), 'a');
      expect(joinAnd(['a', 'b']), 'a and b');
      expect(joinAnd(['a', 'b', 'c']), 'a, b and c');
    });
  });
}
