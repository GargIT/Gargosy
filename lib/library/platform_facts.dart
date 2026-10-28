import '../core/emulator/platform_slugs.dart';
import '../core/romm/romm_models.dart';
import '../l10n/tr.dart';

/// Who made a system and when it came out, for the Platforms cards. RomM's
/// platform data has nothing that fits, so the common systems are listed here.
class PlatformFacts {
  const PlatformFacts(this.maker, [this.year]);
  final String maker;
  final int? year;
}

const _facts = <String, PlatformFacts>{
  'ps': PlatformFacts('Sony', 1994),
  'psx': PlatformFacts('Sony', 1994),
  'ps2': PlatformFacts('Sony', 2000),
  'ps3': PlatformFacts('Sony', 2006),
  'ps4': PlatformFacts('Sony', 2013),
  'psp': PlatformFacts('Sony', 2004),
  'psvita': PlatformFacts('Sony', 2011),
  'nes': PlatformFacts('Nintendo', 1983),
  'snes': PlatformFacts('Nintendo', 1990),
  'n64': PlatformFacts('Nintendo', 1996),
  'ngc': PlatformFacts('Nintendo', 2001),
  'wii': PlatformFacts('Nintendo', 2006),
  'wiiu': PlatformFacts('Nintendo', 2012),
  'switch': PlatformFacts('Nintendo', 2017),
  'gb': PlatformFacts('Nintendo', 1989),
  'gbc': PlatformFacts('Nintendo', 1998),
  'gba': PlatformFacts('Nintendo', 2001),
  'nds': PlatformFacts('Nintendo', 2004),
  '3ds': PlatformFacts('Nintendo', 2011),
  'virtualboy': PlatformFacts('Nintendo', 1995),
  'sms': PlatformFacts('Sega', 1985),
  'genesis': PlatformFacts('Sega', 1988),
  'gamegear': PlatformFacts('Sega', 1990),
  'segacd': PlatformFacts('Sega', 1991),
  'sega32': PlatformFacts('Sega', 1994),
  'saturn': PlatformFacts('Sega', 1994),
  'dc': PlatformFacts('Sega', 1998),
  'xbox': PlatformFacts('Microsoft', 2001),
  'xbox360': PlatformFacts('Microsoft', 2005),
  'tg16': PlatformFacts('NEC', 1987),
  'pcfx': PlatformFacts('NEC', 1994),
  'neogeoaes': PlatformFacts('SNK', 1990),
  'neogeocd': PlatformFacts('SNK', 1994),
  'ngpc': PlatformFacts('SNK', 1999),
  'atari2600': PlatformFacts('Atari', 1977),
  'atari5200': PlatformFacts('Atari', 1982),
  'atari7800': PlatformFacts('Atari', 1986),
  'lynx': PlatformFacts('Atari', 1989),
  'jaguar': PlatformFacts('Atari', 1993),
  'c64': PlatformFacts('Commodore', 1982),
  'amiga': PlatformFacts('Commodore', 1985),
  '3do': PlatformFacts('Panasonic', 1993),
  'colecovision': PlatformFacts('Coleco', 1982),
  'intellivision': PlatformFacts('Mattel', 1979),
  'wonderswan': PlatformFacts('Bandai', 1999),
  'wonderswancolor': PlatformFacts('Bandai', 2000),
  'arcade': PlatformFacts('Arcade'),
};

/// The system's facts; a variant only known through its alias (DSi → DS)
/// keeps the maker, not the parent's year.
PlatformFacts? factsFor(String slug) {
  final own = _facts[slug];
  if (own != null) return own;
  final parent = _facts[canonicalPlatformSlug(slug)];
  return parent == null ? null : PlatformFacts(parent.maker);
}

/// "Sony · 2000 · 412 games", or "412 games" for a system not listed.
String platformLine(Platform p) {
  final f = factsFor(p.slug);
  final count = p.gamesCount == 1 ? tr('1 game') : tr('{0} games', [p.gamesCount]);
  return [?f?.maker, if (f?.year != null) '${f!.year}', count].join(' · ');
}
