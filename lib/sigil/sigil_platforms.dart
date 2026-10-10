/// RomM's platform slug → sigil's (`sigil_platform_from_slug`), for the
/// systems sigil identifies; null for the rest (sigil then guesses from the
/// file extension).
String? sigilPlatformFor(String rommSlug) => _platforms[rommSlug.toLowerCase()];

const _platforms = {
  'psx': 'psx',
  'ps': 'psx',
  'ps1': 'psx',
  'ps2': 'ps2',
  'ps3': 'ps3',
  'psp': 'psp',
  'psvita': 'psvita',
  'vita': 'psvita',
  'ngc': 'gamecube',
  'gc': 'gamecube',
  'gamecube': 'gamecube',
  'wii': 'wii',
  'wiiu': 'wiiu',
  '3ds': '3ds',
  'n3ds': '3ds',
  'switch': 'switch',
  'xbox': 'xbox',
  'xbox360': 'xbox360',
  'dc': 'dreamcast',
  'dreamcast': 'dreamcast',
  'gb': 'gb',
  'gbc': 'gbc',
  'snes': 'snes',
  'n64': 'n64',
};
