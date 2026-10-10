// Adapted from Freegosy (MIT, © 2026 abduznik).
import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/emulator/platform_slugs.dart';
import 'package:gargosy/core/emulator/retroarch_core_list.dart';

/// RomM names platforms by IGDB's slugs (`pc-fx`, `famicom`,
/// `neo-geo-pocket-color`, ...), which Gargosy's lists didn't have, so their
/// games failed with "No Emulator Configured" (as #120 did for
/// `turbografx-cd`).
void main() {
  test('every alias leads to a system a RetroArch core runs', () {
    for (final MapEntry(key: romm, value: own) in kPlatformSlugAliases.entries) {
      expect(getDefaultCoreForSlug(own), isNotNull, reason: '$romm → $own has no default core');
    }
  });

  test('RomM\'s slug gets the same core as Gargosy\'s', () {
    for (final MapEntry(key: romm, value: own) in kPlatformSlugAliases.entries) {
      expect(getDefaultCoreForSlug(romm), getDefaultCoreForSlug(own), reason: romm);
      expect(getCoresForSlug(romm).map((c) => c.id), getCoresForSlug(own).map((c) => c.id), reason: romm);
    }
  });

  test('a few by name', () {
    expect(getDefaultCoreForSlug('pc-fx'), 'mednafen_pcfx_libretro');
    expect(getDefaultCoreForSlug('pc-9800-series'), getDefaultCoreForSlug('pc98'));
    expect(getDefaultCoreForSlug('famicom'), getDefaultCoreForSlug('nes'));
    expect(getDefaultCoreForSlug('neo-geo-pocket-color'), 'mednafen_ngp_libretro');
    expect(getDefaultCoreForSlug('wonderswan-color'), 'mednafen_wswan_libretro');
  });

  test('aliases never shadow a slug Gargosy already knows', () {
    for (final romm in kPlatformSlugAliases.keys) {
      final listed = kRetroArchCores.any((c) => c.platforms.contains(romm));
      expect(listed, isFalse, reason: '$romm is already a core platform');
    }
  });

  test('unknown slugs pass through', () {
    expect(canonicalPlatformSlug('snes'), 'snes');
    expect(canonicalPlatformSlug('some-new-console'), 'some-new-console');
  });
}
