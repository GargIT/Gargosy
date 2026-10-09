import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/romm/romm_models.dart';
import 'package:gargosy/library/platform_facts.dart';

Platform _p(String slug, int count) =>
    Platform.fromJson({'id': 1, 'name': slug, 'slug': slug, 'fs_slug': slug, 'display_name': slug, 'rom_count': count});

void main() {
  test('common systems have a maker and year', () {
    expect(factsFor('ps2')!.maker, 'Sony');
    expect(factsFor('ps2')!.year, 2000);
    expect(factsFor('ngc')!.maker, 'Nintendo');
    expect(factsFor('dc')!.year, 1998);
  });

  test('aliases resolve to the system', () => expect(factsFor('famicom')!.maker, 'Nintendo'));

  test("a hardware variant keeps the maker, not the parent system's year", () {
    expect(factsFor('nintendo-dsi')!.maker, 'Nintendo');
    expect(factsFor('nintendo-dsi')!.year, isNull);
    expect(platformLine(_p('amiga-cd32', 5)), 'Commodore · 5 games');
  });

  test('an unknown slug has none', () => expect(factsFor('my-homebrew'), isNull));

  test('the card line: maker · year · count, or just the count', () {
    expect(platformLine(_p('ps2', 412)), 'Sony · 2000 · 412 games');
    expect(platformLine(_p('my-homebrew', 1)), '1 game');
    expect(platformLine(_p('arcade', 12)), 'Arcade · 12 games');
  });
}
