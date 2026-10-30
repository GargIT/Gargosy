# Ideas

Things Gargosy could do next. Each now has an issue (with its design) in a milestone: 0.6.0 (#223, #224), 0.7.0 downloads and library, 0.8.0 playing and family, 0.9.0 look and feel, 0.10.0 under the hood. A new idea goes here first. Each says what it is, why, where it would hook in, and a rough size (S a day or less, M a few days, L a milestone).

Already on the list elsewhere: Linux (`docs/linux-support.md`), RetroArch Cloud Sync (#5, on hold), Ryujinx's download (#9, on hold), the RomM README listing.

## Family and profiles

- **Age limit per profile** (#224). A profile gets a highest age rating (PEGI/ESRB); games rated above it are hidden from that profile's galleries, shelves, search and the screensaver, and refused at Play. The ratings are already read (`core/romm/game_overview.dart`'s `AgeRating`); an unrated game shows by default, with a switch to hide those too. Changing the limit asks for the PIN of another profile (or this one's). The PIN stays a family lock, not security. **M**
- **Play time limits** (#235). Per profile, minutes per day or a time window. A warning toast before the end, then the game is closed the way the quit buttons close it (`ProcessCloser`, which keeps a state on the emulators that save one on close). Built on `PlayTimeLog`. **M**
- **Profile stats page** (#236). Play time per week and per platform, most played, longest sessions, games finished (RomM's status), achievements this month. From `PlayTimeLog`, RomM's play sessions and `ra_progression`. **M**

## Playing

- **Manuals** (#232). RomM keeps a game's manual (`path_manual`, a PDF). A Manual tab or a button on the game page, read with the controller (pages with LB/RB, zoom with the sticks), and kept on this PC with the ROM's game, in the profile's cache, for offline play. **M**
- **Launch a game from outside** (#223). `Gargosy.exe --play=<rom id> [--profile=<id>]`: opens the profile (PIN if it has one), goes through the normal play flow (pull, launch, sync), and exits after the session when it was started that way. Lets Steam (Add a non-Steam game), Playnite or a desktop shortcut start a game with Gargosy's save sync. A "Create shortcut" item in the game page's ⋯ menu writes a `.lnk` (on the desktop only when asked; it is outside the Gargosy folder, so the PathGuard exception has to be named in the rules). **M**
- **Screenshots to RomM** (#233). After a session, the emulator's new screenshots go up to RomM (`/api/screenshots`) and show in the game page's screenshot strip. Each emulator's screenshot folder is already in the profile's data. **M**
- **One controller layout for every emulator** (#246). A mapping made once in Settings → Controller, written into each emulator's input config at launch (as the folder settings are). The hardest part is each emulator's own format; start with RetroArch, PCSX2, DuckStation and Dolphin. **L**
- **Per-game settings** (#234). Beyond the emulator and core the play screen already remembers: extra arguments, a RetroArch shader preset, widescreen hacks where the emulator has a switch. Kept in the profile's prefs. **M**
- **Multi-disc games** (#230). Make sure every multi-disc game (a folder of `.chd`/`.cue`) starts with an `.m3u` the emulator can switch discs through, written in the profile or temp, never in `roms\`. Check what the copied `GameLaunchService` does today first. **S–M**
- **Continue on another PC, said out loud** (#229). When a profile opens and RomM has a newer state or save from another PC for a recently played game, Home's header says "Continue where you left off on <PC>" with Resume. The data is there (device ids, `ResumeService`). **S**

## Library and downloads

- **Download a whole collection or platform** (#226). "Download all" on a collection's or platform's page, queued through `DownloadsNotifier`, with the total size checked against free space first (`checkSpace`). **S**
- **Check a download** (#225). RomM has each file's hashes (md5, sha1, crc). After a download, check them in an isolate and offer Download again when they don't match; a bad zip is the usual cause of "the game won't start". **S**
- **Free space when it's tight** (#227). When a download doesn't fit, offer to delete games not played for a long time from this PC, largest first, with their saves already on RomM. Storage already lists them (`StoragePlatformScreen`). **M**
- **Download speed limit and a schedule** (#228). A cap (MB/s) and "only at night", for shared connections. In the copied `download_service.dart`. **S–M**
- **Admin tools** (#245). For a RomM admin: start a library scan, upload a ROM from this PC, edit a game's match. All through `romm_service.dart`'s parts, behind RomM's permissions as Delete from RomM is. **M**

## Look and feel

- **Sounds** (#237). Short navigation, open and back sounds (RomM v2 has none, so they'd be Gargosy's own), with a volume setting and off by default. **S**
- **Video previews** (#238). Where RomM has a game's video (ScreenScraper's), play it muted behind the game page's art after a second, and in the screensaver. **M**
- **More languages** (#239). The `tr()` setup takes another language as one file beside `sv.dart`; German, Norwegian, Danish and Finnish are close at hand. A test already fails on a missing text. **S each**
- **Bigger text** (#240). A text size setting (100 %, 125 %, 150 %) for a TV across the room. Every screen has to be checked at 150 %. **M**
- **Notifications** (#241). A small toast when another player shares a save or state of a game this profile has, or a download finishes while a game runs. **S–M**

## Under the hood

- **End-to-end tests against a real RomM** (#242). A RomM container in CI (Linux runner) with a few homebrew ROMs, and a Windows job that logs in, downloads, launches a stub emulator and checks a save round trip. Catches RomM API changes before players do. **L**
- **Emulator updates on their own** (#243). Check installed emulators for a newer release at start (as Gargosy checks itself) and show it in Settings → Emulators, never installed while a game runs. **S–M**
- **winget and Scoop** (#244). A portable manifest for each, made by `release.yml` from the release zip. **S**
- **Send the log with a bug report** (#231). About → "Report a bug" opens the GitHub issue form with the version filled in and the newest log (already redacted) ready to attach. **S**
