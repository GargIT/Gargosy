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

23. [ ] Two Dreamcast games save to the shared VMU. A save sigil can't tie to a game shows under "Unclaimed saves on the shared VMU" on the game page's Saves tab. "Take it" uploads it with that game, and the other game's save on the VMU is untouched. In profile B, the claimed save comes down with the game. *Not tested by hand; #56 closed without it (2026-10-19).*

## Save states between profiles (#58)

With "Save states on RomM" on (Settings → Emulator settings) in both profiles. For each: in profile A, play, save a state to a slot and quit. The state is on RomM. In profile B, the state comes down before launch and Resume (Y on the play screen) starts the game in it. Then make a newer state of the same slot in each profile without syncing between them: the next launch says the state differs and keeps this PC's copy.

24. [x] DuckStation (PS1)
25. [x] PCSX2 (PS2)
26. [x] RetroArch, a PS1 game (Beetle PSX HW or PCSX ReARMed)

## PPSSPP save states (#59)

27. [x] With "Save states on RomM" on: in profile A, play a PSP game in PPSSPP, save a state to a slot and quit. The state is on RomM, with its screenshot on the play screen's States list. In profile B, it comes down before launch and Resume starts the game in it.

## Dolphin save states (#60)

28. [x] With "Save states on RomM" on: in profile A, play a GameCube game in Dolphin, save a state to a slot (Shift+F1) and quit. The state is on RomM. In profile B, it comes down before launch and Resume starts the game in it.
29. [x] The same with a Wii game.

## mGBA save states (#61)

30. [x] With "Save states on RomM" on: in profile A, play a GBA game in mGBA, save a state to a slot (Shift+F1) and quit. The state is on RomM, with its picture on the play screen's States list. In profile B, it comes down before launch and Resume starts the game in it.
31. [x] The same with a Game Boy (or Game Boy Color) game.

## MAME save states (#62)

32. [x] With "Save states on RomM" on: in profile A, play an arcade game in MAME, save a state (Shift+F6, then a key, e.g. 1; Shift+F7 loads) and quit. The state is on RomM. In profile B, it comes down before launch and Resume starts the game in it.

## Flycast save states (#63)

33. [x] With "Save states on RomM" on: in profile A, play a Dreamcast game in Flycast, save a state and quit. The state is on RomM, with its picture on the play screen's States list. In profile B, it comes down before launch and Resume starts the game in it (Flycast loads the slot at boot). Afterwards, Flycast's own "load state on start" setting is as it was (the Resume setting is for that launch only).

## Azahar save states (#64)

34. [x] With "Save states on RomM" on: in profile A, play a 3DS game in Azahar, save a state to a slot and quit. The state is on RomM. In profile B, the play screen's States list shows it with "load it from Azahar's menu" (A doesn't pick it). Start the game: the state is in Azahar's Load State menu under that slot, and loading it continues where A stopped.

## melonDS save states (#65)

35. [x] With "Save states on RomM" on: in profile A, play a DS game in melonDS, save a state to a slot and quit. The state is on RomM. In profile B, the play screen's States list shows it with "load it from melonDS's menu" (A doesn't pick it). Start the game: the state is in melonDS's Load State menu under that slot, and loading it continues where A stopped.

## ares save states (#66)

36. [x] With "Save states on RomM" on: in profile A, play a game in ares (e.g. N64), save a state to a slot and quit. The state is on RomM. In profile B, it comes down before launch and Resume starts the game in it.

## sigil required, old save code removed (#57)

37. [x] Rename `sigil.dll` beside `Gargosy.exe` and start Gargosy: it shows "Gargosy can't load sigil.dll" with the path, and doesn't start. Rename it back: Gargosy starts as before.

For 38–40, profile B is a second profile signed in to the **same RomM user** as A: it stands for another PC of the same player. (Another RomM user doesn't see A's saves or states, public or not: #92.)

38. [x] On PCSX2 (PS2), DuckStation (PS1), Dolphin (GameCube), PPSSPP (PSP) and mGBA (Game Boy): in profile A, save in-game and quit; the save is on RomM. In profile B, start the game: it comes down before launch and the game finds it.
39. [x] With "Save states on RomM" on in both profiles, the same with a state on each of them: in profile A, save a state and quit; the state is on RomM. In profile B, Resume starts the game in it.
40. [x] A Wii game in Dolphin and a PS2 game in RetroArch (LRPS2): the save round trip of row 38.

## Platform page: filter and sort bar (#95)

41. [x] On PlayStation 2, type "hack" in the filter box with the keyboard: shortly after typing stops, the .hack games show, also ones beyond the first page. With a controller, A on the box opens the on-screen keyboard and the filter applies when it closes.
42. [x] Turn On this PC on: only this platform's downloaded games show, with their count on the switch. Sort by Downloaded puts the newest download first. With RomM stopped (or the PC offline), the switch still works.
43. [x] Sort by Size, Players, Length and My rating: the order is the expected one, and the direction button turns it round. Games without the value (no HowLongToBeat time, no rating) come last either way.

## Platform page: header and tabs (#95)

44. [x] Open PlayStation 2: the header shows its logo, Console · Sony · Generation 6, In library, On this PC (your downloaded PS2 games), On disk and Firmware. Random opens a PS2 game.
45. [x] Scroll the games: the header goes, the name sits in the tab row, and the filter and sort bar stays. Back at the top, the header returns. With a controller, D-pad up from the first row reaches the bar, then the tabs, then Random.
46. [x] Firmware / BIOS marks what's in `bios\`. Get missing from RomM brings the rest, and they show as On this PC.
47. [x] Emulator: change the emulator (with two installed) or RetroArch's core; Settings → Emulator settings shows the same, and a game without "Always for this game" plays in it. An uninstalled emulator's Install under Emulators opens Settings → Emulators.
48. [x] LB/RB switch tabs. Move to a cover, RB, move in the firmware list, LB: focus is back on that cover; RB: back in the list.

## A–Z rail (#95)

49. [x] On a big platform sorted by Name, click a letter far down (T): the page jumps to the first T game, also when it wasn't loaded yet. `#` jumps to games starting with a digit or symbol; letters without games are greyed.
50. [x] With a controller: D-pad right from the last column reaches the rail, up/down picks a letter (skipping greyed ones), A or left jumps into the grid at it. X from a cover goes to the rail at that game's letter. Sorted by anything else, there's no rail. On this PC, the rail jumps within the downloaded games.

## Cover marks and folded versions (#95)

51. [x] A game with two or more versions on RomM (e.g. USA and Europe) shows as one card with the count top left and its region (`USA`) bottom left; a favourite has the heart and a downloaded one the on-this-PC mark.
52. [x] Open a folded game with none of its versions downloaded: RomM's version opens, and Version on its page lists the others; pick one to go to its page and download it. With one version downloaded, the card opens that one. With two downloaded, it asks "Which version?".
53. [x] Collections and Favourites have the bar, the A–Z rail (by name) and the marks.
54. [x] Put a game's file in `roms\ps2\` by hand, or download one in another profile: it has the ✓ but isn't counted On this PC. On PlayStation 2 with On this PC on, Scan says "Found 1 more on this PC." and the game is listed. Scan isn't there on a collection or with On this PC off.

## Other players' saves (#92)

For these, a second RomM user (player A) on the same server, with a save of a game made public in RomM's web UI. Player B is a Gargosy profile of another RomM user.

55. [x] In B's profile, the game's play screen and Saves tab list A's save under From other players, with A's name. B's own saves come first, and the Saves count doesn't include A's.
56. [x] With a save of B's own on this PC, pick A's save and Play: it asks "Play A's save?" first. The game starts in A's save. After quitting, the save is on RomM under B, and A's save on RomM is unchanged.
57. [x] On the Saves tab, X on A's save puts it on this PC (B's save is backed up first); hold A does nothing on it. A makes the save private again: B no longer sees it.
58. [x] A makes a state public (PCSX2, DuckStation, Dolphin, PPSSPP, mGBA or MAME). In B's profile, the play screen's States list shows it under From other players with A's name; the States count is B's own. Resume it: the game starts in A's state, and B's own states are unchanged.
59. [x] The same with a RetroArch (or ares, Flycast) state: it goes into the first free slot of B's (Slot 1 when B has none), the game starts in it, and after quitting it's B's state in that slot (on RomM under B with state sync on). B's state in A's slot number, if any, is unchanged.
60. [x] In B's profile, on the game's Saves tab, Y on one of B's saves on RomM: it says it's shared and gets the teal "shared" tag. In A's profile (or RomM's web UI as A), B's save shows under From other players / is public. Y again: it stops being shared, and A no longer sees it. The same on the States list for a state of B's on RomM. With the mouse, a click on B's RomM save offers Share on RomM / Stop sharing.

## Delete this PC's saves and states (#94)

61. [x] A GBA game in mGBA (or a SNES game in RetroArch) with a save: on the Saves tab, hold A on its This PC row and confirm. The row goes, a new backup row appears, and the save file is gone from the emulator's save folder. Play again: RomM's save comes back.
62. [x] Two PS2 games in PCSX2 with saves on the same memory card: hold A on one game's This PC row and confirm. Its save folders (`BASLUS-…`) are gone from `memcards\Mcd001.ps2`, the other game's stay and still load in PCSX2, and a copy of the folders is in the profile's `backups\deleted\<time>\`.
63. [x] On the States list: hold A on one of your states (on this PC and RomM) and confirm: it's gone from the list, from the emulator's state folder and from RomM. One only on RomM goes the same way. Another player's state has no delete.
64. [x] A Game Boy game in mGBA (or in RetroArch) with a save: hold A on its This PC row and confirm. The row goes, a backup row appears, the game's `.sav` (RetroArch: `.srm`) is gone and other games' saves stay. Play again: RomM's save comes back without asking about a changed save.
65. [x] Two PS1 games in DuckStation (or RetroArch) on one shared card: hold A on one game's This PC row and confirm. Its save is gone from the card, the other game's still loads, and the whole card as it was is in `backups\deleted\<time>\`.
66. [x] A GameCube game in Dolphin (or a Dreamcast game in Flycast): hold A on its This PC row: it says why it can't be deleted, and nothing changes.

## DSi games in melonDS DS (#114)

67. [x] A DSi platform game (Zuma's Revenge! (USA)): its play screen offers RetroArch with melonDS DS only, chosen already; Play downloads the core the first time, and the game starts.
68. [x] Save in it and quit: `<game>.public.sav` is in the profile's RetroArch `saves\` and on RomM (the Saves tab). Delete it on this PC, play again: RomM's save comes back as `.public.sav` (no new `.public.srm`) and the game has it.
69. [x] On the DSi platform's page, Emulator tab: RetroArch's core is melonDS DS; a DS game still starts in the DS platform's core.
70. [x] Zuma's Revenge! (Europe, Australia) on this PC: its Details tab has a DSiWare row asking for a NAND from Europe or Australia; Zuma's Revenge! (USA) asks for USA.
71. [x] Play a DSi game in RetroArch: the profile's `system\dsi_nand.bin` is its own copy now (`bios\dsi_nand.bin` keeps its date after playing), and the game still starts.
72. [x] With a European NAND in `bios\` under its own name beside `dsi_nand.bin`: Zuma's Revenge! (Europe, Australia) starts, and the USA copy still does.

## A–Z rail: the current letter (#118)

73. [ ] A platform's games sorted by name: scroll with the mouse wheel, then with the D-pad. The rail lights the letter you're at and follows; after a jump to T it lights T.

## DSiWare not in standalone melonDS (#119)

74. [ ] Zuma's Revenge! (USA): its play screen offers RetroArch (melonDS DS) only, not melonDS, though melonDS is installed. A DSi or DS cartridge game still offers melonDS.
75. [ ] A DSiWare game you played in standalone melonDS before (Zuma's Revenge! (Europe, Australia)): its play screen picks RetroArch now, not melonDS, and Play starts it there.

## Collections page (#121)

76. [ ] The Collections tab: your collections and the shared ones in the panel, Favourites first; RomM's virtual ones below it by type (Franchise, Genre …). The covers, the smart / shared / player marks and "N on PC" look right.
77. [ ] Filter by name, Kind (Smart, Virtual) and Whose (Mine, Others'); Whose is greyed with Virtual; Sort by Games and Recently updated. All of it with the controller.
78. [ ] A on a smart and on a virtual collection opens its games; Y on one opens a random game of it.
79. [ ] A collection's page: its mosaic, name, kind, Shared / By you (or the owner), description (a smart one's filters), games and on this PC; Random opens one of its games. Scroll: the header goes and the name stays above the bar; up again, it comes back. B goes back to the tab.
