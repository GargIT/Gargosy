# Notices

Gargosy is MIT licensed: see [LICENSE](LICENSE).

Gargosy contains code adapted from **Freegosy** (https://github.com/abduznik/Freegosy),
Copyright (c) 2026 abduznik, under the MIT License: see [LICENSES/Freegosy-MIT.txt](LICENSES/Freegosy-MIT.txt).
Each adapted file starts with `// Adapted from Freegosy (MIT, © 2026 abduznik).`

`gamecontrollerdb.txt` is the SDL GameController DB; its licence is in
[LICENSES/SDL_GameControllerDB.txt](LICENSES/SDL_GameControllerDB.txt).

`7zr.exe` is 7-Zip's standalone extractor, Copyright (C) 1999-2025 Igor Pavlov, under the
GNU LGPL (source at https://www.7-zip.org); its licence is in [LICENSES/7-Zip-LGPL.txt](LICENSES/7-Zip-LGPL.txt). Gargosy
uses it unchanged to unpack emulator downloads.

`sigil.dll` is argosy-sigil v1.0.0 (MPL-2.0), used unchanged, which reads game ids and moves saves. Its
source code is available at https://github.com/rommapp/argosy-sigil/tree/v1.0.0 (and in this repository's
`third_party/argosy-sigil`). Its licence and those of the libraries it bundles (zlib, zstd, LZMA SDK,
tiny-AES-c, libchdr, and dr_flac inside libchdr, public domain) are in [LICENSES/argosy-sigil-MPL-2.0.txt](LICENSES/argosy-sigil-MPL-2.0.txt)
and [LICENSES/libchdr.txt](LICENSES/libchdr.txt).

`gamepads_windows_plugin.dll` is built from gamepads_windows 0.3.2 (https://github.com/flame-engine/gamepads),
Copyright (c) 2023 Blue Fire, under the MIT License, patched so Gargosy doesn't crash when it closes. The
patched source and its licence are in this repository's `third_party/gamepads_windows` (`GARGOSY.md` lists the
changes).

`pdfium.dll` is PDFium (chromium/8125, BSD-3-Clause, from https://github.com/bblanchon/pdfium-binaries, MIT),
used unchanged through pdfrx (MIT) to show game manuals. Its licences and those of the libraries it bundles
are in [LICENSES/PDFium.txt](LICENSES/PDFium.txt).

Gargosy's look follows the design token values of RomM's v2 web UI (https://github.com/rommapp/romm).
No RomM code, stylesheets, icons or logos are included.

Gargosy is built with Flutter and Dart packages under their own licences (BSD, MIT, Apache-2.0 and
others). Flutter gathers them into `data\flutter_assets\NOTICES.Z` in the app folder (gzip text); in Gargosy,
About → Dart and Flutter packages lists them.
