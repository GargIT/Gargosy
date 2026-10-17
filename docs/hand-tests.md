# Hand tests for 0.2.0

These are the tests left for a person on the open issues. Everything else is covered by `flutter test` and the probes noted in each issue. Tick a row (`[x]`) once it passes. When every row of an issue is ticked, the issue can be closed. A failure goes in the issue, with the log (Settings → About → Open log folder).

The test install is `C:\Retro\apps\gargosy` (built from `main`). For tests that use two profiles, make two profiles signed in to the same RomM user, unless the row says otherwise.

## Logging (#1)

1. [x] Sign in with a password, pair a device with the QR code, and sign in to RetroAchievements. Open the log in `userdata\app\logs\`, and check that no token, password or API key appears in it.
2. [x] Lines written while a profile is open carry its `[p:…]` tag, and lines from the profile picker carry none.

## RetroArch saves through sigil (#7)

For each system below, play a game in RetroArch through Gargosy, save in-game and quit. Then:

- check that the save is on RomM in the `autosave` slot;
- delete the save on this PC;
- start the game again and check that the save comes back;
- open the game in RomM's web player and check that the save loads there.

3. [x] Game Boy
4. [x] Game Boy Color, a game with a clock (e.g. Pokémon Gold/Silver/Crystal)
5. [x] Nintendo 64
6. [x] PlayStation (PS1)
7. [x] PlayStation 2 with the LRPS2 core

## Folder link on a USB stick (#8)

8. [ ] Copy Gargosy to a FAT32 or exFAT USB stick and start Eden, Azahar, Cemu or melonDS from it. The launch is refused with "A folder link can't be made … The drive may be FAT32 or exFAT", and nothing is written. *Not tested: no FAT32 or exFAT drive at hand; #8 closed without it (2026-10-16).*

## Ryujinx (#9)

9. [ ] Settings → Emulators → Download Ryujinx (from Ryubing). It installs and starts. *On hold: the download is off while Ryubing's server doesn't answer.*
10. [ ] Play a Switch game in profile A and save. Then play it in profile B: B has no save from A. The save is on RomM. Start a game once before a RomM save can be put in place.

## RPCS3 (#10)

11. [x] Play a PS3 game in profile A and save. In profile B the save isn't there. The save is on RomM.
12. [x] While a game runs, nothing in `emulators\rpcs3-firmware\dev_flash` changes (compare the modified dates before and after).

## ScummVM (#11)

13. [x] Play a game downloaded from RomM as a `.scummvm` file, then save and load in-game.
14. [x] Play a game that is a folder, then save and load in-game.
22. [x] Save in a ScummVM game and quit: the save is on RomM. In profile B, the game starts with that save (pulled into `saves\<game>\`). Saves made before this fix sit loose in `saves\` and aren't synced; move them into the game's folder.

## Eden, Azahar, Cemu, melonDS (#12–#15)

For each one: play a real game in profile A and save. Then play it in profile B, which starts without A's save. A's save is on RomM.

15. [x] Eden (Switch) (#12)
16. [x] Azahar (3DS) (#13)
17. [x] Cemu (Wii U) (#14)
18. [x] melonDS (DS) (#15)

## Updates (#16)

These rows need preview releases published on GitHub.

19. [x] Settings → About → Updates: the updater window shows its progress and starts Gargosy again when it's done.
20. [x] On a preview build, About shows the preview version, and its Updates block shows the Preview channel.
21. [x] A real update from preview N to N+1. Afterwards, the profiles, ROMs, emulators and BIOS files are all still there, and What's new (#3) opens once with N+1's changes.

## Unclaimed saves on Flycast's shared VMU (#56)

Flycast with its per-game VMU setting off (`PerGameVmu = no` in the profile's `emu.cfg`), so every game shares one VMU.

23. [ ] Two Dreamcast games save to the shared VMU. A save sigil can't tie to a game shows under "Unclaimed saves on the shared VMU" on the game page's Saves tab. "Take it" uploads it with that game, and the other game's save on the VMU is untouched. In profile B, the claimed save comes down with the game.

## Save states between profiles (#58)

With "Save states on RomM" on (Settings → Emulator settings) in both profiles. For each: in profile A, play, save a state to a slot and quit. The state is on RomM. In profile B, the state comes down before launch and Resume (Y on the play screen) starts the game in it. Then make a newer state of the same slot in each profile without syncing between them: the next launch says the state differs and keeps this PC's copy.

24. [ ] DuckStation (PS1)
25. [ ] PCSX2 (PS2)
26. [ ] RetroArch, a PS1 game (Beetle PSX HW or PCSX ReARMed)

## PPSSPP save states (#59)

27. [ ] With "Save states on RomM" on: in profile A, play a PSP game in PPSSPP, save a state to a slot and quit. The state is on RomM, with its screenshot on the play screen's States list. In profile B, it comes down before launch and Resume starts the game in it.

## Dolphin save states (#60)

28. [ ] With "Save states on RomM" on: in profile A, play a GameCube game in Dolphin, save a state to a slot (Shift+F1) and quit. The state is on RomM. In profile B, it comes down before launch and Resume starts the game in it.
29. [ ] The same with a Wii game.

## mGBA save states (#61)

30. [ ] With "Save states on RomM" on: in profile A, play a GBA game in mGBA, save a state to a slot (Shift+F1) and quit. The state is on RomM, with its picture on the play screen's States list. In profile B, it comes down before launch and Resume starts the game in it.
31. [ ] The same with a Game Boy (or Game Boy Color) game.

## MAME save states (#62)

32. [ ] With "Save states on RomM" on: in profile A, play an arcade game in MAME, save a state (Shift+F7, then a key, e.g. 1) and quit. The state is on RomM. In profile B, it comes down before launch and Resume starts the game in it.

## Flycast save states (#63)

33. [ ] With "Save states on RomM" on: in profile A, play a Dreamcast game in Flycast, save a state and quit. The state is on RomM, with its picture on the play screen's States list. In profile B, it comes down before launch and Resume starts the game in it (Flycast loads the slot at boot). Afterwards, Flycast's own "load state on start" setting is as it was (the Resume setting is for that launch only).

## Azahar save states (#64)

34. [ ] With "Save states on RomM" on: in profile A, play a 3DS game in Azahar, save a state to a slot and quit. The state is on RomM. In profile B, the play screen's States list shows it with "load it from Azahar's menu" (A doesn't pick it). Start the game: the state is in Azahar's Load State menu under that slot, and loading it continues where A stopped.

## melonDS save states (#65)

35. [ ] With "Save states on RomM" on: in profile A, play a DS game in melonDS, save a state to a slot and quit. The state is on RomM. In profile B, the play screen's States list shows it with "load it from melonDS's menu" (A doesn't pick it). Start the game: the state is in melonDS's Load State menu under that slot, and loading it continues where A stopped.

## ares save states (#66)

36. [ ] With "Save states on RomM" on: in profile A, play a game in ares (e.g. N64), save a state to a slot and quit. The state is on RomM. In profile B, it comes down before launch and Resume starts the game in it.
