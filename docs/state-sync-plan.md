# Save states on RomM for more emulators — spec and plan

Status: **proposal**, written 2026-10-10. Nothing here is built yet. Revised the same day with two decisions (§2.1).

## 1. Where we are

State sync sends an emulator's save states to RomM's `/api/states` and brings them back before a launch. It runs separately from game saves. Today it is per emulator and **off by default**; the switches are in Settings → Emulators → "Save states on RomM". This plan replaces them with one switch (§2.1).

The machinery is generic. `StateSyncService` handles hashing, records, transfers, backups and conflicts. `ResumeService` builds the Resume list. An emulator only has to supply the parts listed below.

| Piece | Where | What it answers |
|---|---|---|
| `StateSyncCapable` mixin on the save strategy | `core/save/state_sync_capable.dart` | state folder, which file names belong to the game, valid-state check, slot, version/format, screenshot |
| `supportsStateSync` on the emulator strategy | `core/emulator/emulator_strategy.dart` | shows the emulator as able to sync states (`state_sync_gating_test` checks this agrees with the mixin) |
| `supportsStateLoadOnLaunch` + `stateLoadArgs` + `canLoadState` | same | Resume / "start from this state" on the play screen. `ResumeService` lists states only for emulators that have this |
| `_stateSyncEmulators` | `ui/screens/settings/emulators_section.dart` | the Settings switches (one per emulator today; one global switch after S0.4) |
| Sigil wrapper | `sigil/sigil_save_strategy.dart` | `_SigilStateSaveStrategy` passes the state methods through to the wrapped strategy, so emulators that sigil covers keep states with their old strategy |

Three emulators are wired today: **DuckStation, PCSX2 and RetroArch**.

### Does DuckStation work? Reading the code says yes. A real run hasn't checked it yet.

Following the code for a Gargosy profile:

1. **State folder.** `EmulatorLayout('duckstation')` has no `saveView`, so the save view's "exe folder" is `profiles\<id>\emulators\duckstation`. `DuckstationSaveStrategy._getBaseDir` picks that folder when `portable.txt` or `settings.ini` is in it. The `_Swap` launch config copies the profile's `settings.ini` back there after every session, so from the second launch on the base folder is `<data>`. `stateDirectory` is `<data>\savestates`.
2. **Where DuckStation writes.** `_duckstationFolders` sets `[Folders] SaveStates = <data>\savestates` before launch. This matches step 1.
3. **First launch of a fresh profile.** `<data>\settings.ini` doesn't exist yet, so `_getBaseDir` falls back to `%LOCALAPPDATA%\DuckStation`. `sandboxedPlatform` points `LOCALAPPDATA` at `profiles\<id>\emulators`, so the fallback is `profiles\<id>\emulators\DuckStation`. That is the same folder as `<data>`, but **only because Windows paths ignore case**. It works, but by luck. Plan step S0.2 makes it explicit.
4. **Identity.** States are named `SERIAL_N.sav` / `SERIAL_resume.sav`. The serial comes from RomM's `titleId` through `GameIdResolver`, else from sigil (`RomGameIds`). A game with neither has no state sync; the log says "cannot identify the game".
5. **Resume.** DuckStation takes `-statefile <path>` (`supportsStateLoadOnLaunch`). The auto slot `SERIAL_resume.sav` is written on exit when DuckStation's "Save State On Exit" is on, which is the default.
6. **Tests.** The pieces have unit tests (`duckstation_state_sync_capable_test`, `duckstation_strategy_state_load_test`, `state_sync_service_*`). **No test runs them through the profile layer.** Nothing checks that `ProfileSaveDirectories` + the `_Swap` config + `DuckstationSaveStrategy` agree on `<data>\savestates`.

The tests can't cover the following, which is why a manual check (S0.1) is the first step:
- the switch is on for the profile (it's off by default);
- states actually appear on RomM after a session and come down on another PC or profile;
- `-statefile` boots into the state with the DuckStation build Gargosy installs.

### A problem found along the way: states riding in game saves

`PlayEngine` syncs saves with `syncMode: 'both'`. Freegosy's save strategies read that as "game saves **and** states", so states can end up inside the save zip:

- **Dolphin** (`dolphin_save_strategy.dart`, "Handle States") adds `StateSaves\<GameID>.sNN` to the save upload. Sigil covers GameCube, but **Wii games still go through this path**.
- **PPSSPP** (`ppsspp_save_strategy.dart`) adds `PPSSPP_STATE\<rom stem>.ppst` when that file exists. Sigil covers PSP, so this is reached only when sigil falls back.
- **PCSX2** already excludes its states (`pcsx2_states_excluded_from_saves_test`), and **ares** drops `.bs1`–`.bs9`.

A state inside a save zip is several MB per upload. It gets restored over the player's live state without asking. Worst of all, it hides the state from the state UI. It must stop before those emulators get real state sync (S0.3).

## 2. Goal

Each supported emulator that has save states should:

1. upload its states for a game to RomM after a session, and bring them down before the next launch, through `StateSyncService`, under the one global switch;
2. show them in the play screen's States list, with slot, time, screenshot and a version/format tag where the file records one;
3. boot straight into a chosen state (Resume) where the emulator has a command line for it.

### 2.1 Decisions

**One switch for all emulators.** State sync is one profile setting, "Sync save states with RomM", not one per emulator. When it is on, every emulator that supports state sync syncs its states. When it is off, none does. Whether an emulator supports it comes from its strategy only (`supportsStateSync` + `StateSyncCapable`), never from a list in the UI. A new emulator that gains state support is covered by the switch with no settings change.

**States on this PC always work.** With the switch off, an emulator still lists the game's states on this PC, and Resume / "start from this state" still boots into one when the emulator supports load-on-launch. Turning sync off means only that nothing goes to or comes from RomM. States on RomM are not shown while it is off.

The code already does most of the second rule:
- `ResumeService.entriesFor` lists local entries without looking at the switch; only the RomM merge is gated (`syncing`).
- `PlayController.resume` calls `pullStates`, which returns an empty `StatePull` when sync is off.
- `checkBeforeLaunch` only checks that the local file is there.

No test pins this down yet (S0.5). The one place that breaks it is RetroArch: with its switch off, `RetroArchSaveStrategy` adds states **into the save zip** (`!_stateSyncOn` in `getSaveFiles`). With sync off they would still go to RomM, inside the saves, and be restored over local states. Under the rules above, states never ride in saves, whatever the switch says (S0.3).

Non-goals:
- Converting states between emulators. A state belongs to the emulator that wrote it; `StateSyncService` already keys records by emulator id.
- States from RomM's web player (EmulatorJS).
- Emulators without save states: Xenia, xemu (it has snapshots inside its qcow2 HDD, not files), Cemu, Ryujinx, Eden.

## 3. Candidates

These facts come from the emulators' documentation and source as I remember them. **Each must be checked against the build Gargosy installs** (S1.1 for each emulator), the same way `docs/emulator-profiles.md` was.

| Emulator | Platforms | State files (in the profile) | Game key | Load on launch | Screenshot / version | Value | Effort |
|---|---|---|---|---|---|---|---|
| **PPSSPP** | PSP | `<data>\PSP\PPSSPP_STATE\<DISCID>_<DISCVER>_<N>.ppst` (slots 0–4), `…_undo.ppst` | disc ID (`ULUS10041`) from RomM `titleId`, else sigil, else PARAM.SFO | `--state=<file>` (to verify) | `.jpg` sidecar with the same stem; header has the version | high | low |
| **Dolphin** | GC, Wii | `<data>\StateSaves\<GameID>.s01`–`.s10`, `lastState.sav` (undo) | 6-char Game ID (RomM `titleId`, else disc header bytes 0–5) | `-s <file>` / `--save_state=<file>` | no screenshot; header records the Dolphin version (to verify) | high | low–medium |
| **mGBA** | GBA, GB, GBC | `<data>\states\<rom stem>.ss1`–`.ss9` (`savestatePath` is set on the command line) | ROM file stem (like RetroArch) | `-t <file>` | the state is a PNG with the state in a chunk, so the file is its own screenshot | medium | low |
| **MAME** | Arcade | `<data>\sta\<driver>\<name>.sta`, `auto.sta` with `-autosave` | driver name (= ROM set stem; already used for `-rompath`) | `-state <name>` (a slot name, not a path) | header `MAMESAVE`; no screenshot | medium | medium (the slot-name launch arg, the per-driver folder) |
| **Flycast** | Dreamcast, Naomi | `<data>\states\<rom stem>.state`, `<stem>_N.state` | ROM file stem | no CLI option known. Possible route: transient `-config config:Dreamcast.AutoLoadState=yes` with the chosen state copied into slot 0 (to verify) | to verify | medium | medium |
| **ares** | many | `.bs1`–`.bs9` in `<data>\saves` (already kept out of save sync) | ROM stem | none known | no | low | low (sync only, no Resume) |
| Azahar, melonDS, RPCS3 | 3DS, DS, PS3 | — | — | — | — | later: none of these is profile-supported yet (see `emulator-profiles.md`, "Not probed") | — |

Suggested order: **PPSSPP → Dolphin → mGBA → MAME → Flycast → ares**. The first three have a clear game key, a load-on-launch option and a simple file layout. Each one is a self-contained change.

### Notes per emulator

- **PPSSPP.** The disc version in the name (`_1.00_`) means a re-dump with another version is a different game to PPSSPP. The matcher keys on the disc ID and the version both, as the file name does. `stateScreenshot` reads `<stem>.jpg`. The undo file (`_undo.ppst`) is never synced; the matcher rejects it. The save strategy's `.ppst`-in-saves branch is removed (S0.3).
- **Dolphin.** One strategy serves both GC and Wii. Sigil wraps GC, so the strategy that sigil wraps must expose the state methods. That means `forEmulator` must get a Dolphin base that is `StateSyncCapable`, which happens automatically once `DolphinSaveStrategy` mixes it in. `lastState.sav` and `.dtm` are never synced. The "Handle States" branch in `getSaveFiles` is removed (S0.3). Dolphin also has "Save State to Oldest Slot", which rotates slots; this is harmless because each slot is its own file.
- **mGBA.** The same states are shared by GB/GBC/GBA. Sigil wraps mGBA for GB/GBC saves, and states stay with the base strategy (as for DuckStation). `.ss0` is the auto/"load last" slot if one exists (to verify). The matcher needs the stem rules from RetroArch (`getRomStem` and the ROM file's stem).
- **MAME.** `-state <name>` loads `sta\<driver>\<name>.sta`, so `stateLoadArgs` must pass the slot name, not a path. The launch config must keep `-state_directory` (it does). `canLoadState` accepts only names in that folder.
- **Flycast.** If the AutoLoadState route doesn't work, Flycast gets sync only, no Resume (as ares). Note that `ResumeService` skips emulators without load-on-launch altogether, so today a sync-only emulator's states would not be listed at all. S1.6 decides whether to list them (shown, not resumable) or leave them out.

## 4. Plan

### Stage 0: make what exists solid (do this first)

- **S0.1 Manual check of DuckStation, PCSX2 and RetroArch on Windows.** (Can run before or after S0.4; with the old switches, turn each one on.) For each: turn sync on, play, save to a slot, exit. Check the state is on RomM (`/api/states?rom_id=`). On a second profile or PC, check it comes down before launch, Resume boots into it, and a conflict asks. Record the result in a new "Save states" column in `docs/emulator-profiles.md`.
- **S0.2 A profile-level state test per wired emulator.** New `test/unit/profile_state_dirs_test.dart`: build `ProfileSaveDirectories` and `ProfileLaunchDirectories` for a temp root. Run the launch config's `prepare` (recording the args and written keys). Assert that `strategy.stateDirectory(game, rom)` is exactly the folder the emulator is told to write states to:
  - DuckStation: the `SaveStates` key;
  - PCSX2: `-datapath` + `PCSX2\sstates`;
  - RetroArch: `savestate_directory` + the core subfolder.

  Make DuckStation's first-launch path explicit, not reliant on case: either add a `settings.ini` seed (empty) through `EmulatorLayout.seed`, or give the layout a `saveView` that always finds the profile copy. The test must not depend on Windows ignoring case: it should pass on a case-sensitive file system too.
- **S0.3 Keep states out of game saves, always.** Gargosy's sync passes `'saves'` (or strips the state branches) for Dolphin and PPSSPP, as was done for PCSX2. RetroArch's "states in the save zip when its switch is off" branch goes too (§2.1). States reach RomM only through `StateSyncService`, and only with the switch on. Tests are modelled on `pcsx2_states_excluded_from_saves_test`: Dolphin (Wii game with `StateSaves\RSBE01.s01`) and PPSSPP. Check that existing RomM saves with a state inside still restore their real save; the state entry is ignored.
- **S0.4 One global switch.** *(Done: the switch is in Settings → Emulator settings.)*
  - `StateSyncService`: a single profile pref `state_sync_enabled` (`StateSyncService.enabledKey` without an argument). `isEnabledFor(emulatorId)` becomes `isEnabled`. `availabilityReason` still names the emulator when its strategy isn't `StateSyncCapable` ("no state-sync support for …"). When the switch is off it says "state sync is off: switch it on in Settings → Emulators".
  - Every reader of the old keys moves to the global one: `ResumeService` (`syncing`), `RetroArchSaveStrategy._stateSyncOn` (which S0.3 makes save-only anyway), `PlayEngine.stateSyncAvailable` / `pullStates` (through `isAvailableFor`).
  - **Migration:** on the first read, if the global key is missing and any `state_sync_enabled_<id>` is true, the global key is set to true. Someone who turned it on for one emulator wanted sync. The old keys are then removed from the profile's `prefs.json`. This runs once, in `StateSyncService`'s constructor or a small `migrateStateSyncPref(prefs)` called where the profile's prefs open.
  - **Settings:** one toggle, "Sync save states with RomM", replacing the per-emulator rows and `_stateSyncEmulators`. The note under it names the installed emulators that sync states (from the registry's `supportsStateSync`) and says the others keep states on this PC only. CLAUDE.md: never hardcode emulator behaviour in the UI.
  - Tests: `settings_screen_test` (one toggle, the pref it writes, the note lists only capable installed emulators), a migration test (old key on → global on, old keys gone; nothing set → off), and the test helpers that set `enabledKey(id)` (`state_sync_test_env`, `resume_service_test`, `state_sync_service_unsafe_names_test`) move to the global key. `state_sync_service_pull_test`'s "needs a StateSyncCapable strategy AND the toggle" stays, with the global toggle.
- **S0.5 Local states with sync off: a test that keeps it so.** Sync off, a DuckStation (and a RetroArch) state on disk:
  - `entriesFor` lists it, and RomM's list is never called;
  - `PlayController.resume` launches with `-statefile <path>` (RetroArch: its slot args);
  - no upload happens after the session (`pushStates` isn't reached, and the save upload holds no state file).

  And a widget test: the play screen's States tab shows the local state and Y resumes it with the switch off; "Sync save states now" stays hidden.

### Stage 1: one emulator at a time (repeat S1.1–S1.7 per emulator, in the order above)

- **S1.1 Probe.** With the build Gargosy installs, run a game in a profile, save to slots 1 and 2, and exit with the auto state on if it has one. Write down the file names, folder, header bytes, screenshot and launch option. Add a row to `docs/emulator-profiles.md` (the "Save states" column). Drop or downgrade the emulator (sync without Resume) if the facts in §3 are wrong.
- **S1.2 State file reader** (only where there is a header worth reading): `core/save/strategies/<emu>_state_file.dart`, like `duckstation_state_file.dart`. Magic check, version/format, screenshot. Never throws.
- **S1.3 `StateSyncCapable` on the save strategy:** `stateDirectory`, `stateFileMatcher` (rejects separators, undo, temp and backup files, and other games), `looksLikeValidState`, `slotOf`, `describeState`, `stateScreenshot`. Name these Gargosy changes in the file's header comment, below the Freegosy line.
- **S1.4 Emulator strategy:** `supportsStateLoadOnLaunch`, `stateLoadArgs`, `canLoadState` where §3 has a launch option. Override the `…ExtraArgs` launch variants only (see the doc comment on `supportsStateLoadOnLaunch`). Check the args survive `ProfileLaunchDirectories` (they go before `gameArgs`; MAME's `gameArgs` is special).
- **S1.5 Sigil.** If sigil wraps the emulator (Dolphin GC, PPSSPP, mGBA GB/GBC, Flycast), add a case to `sigil_save_strategy_test` that the wrapper is `StateSyncCapable` and passes the calls through.
- **S1.5b Turn sync on for it.** `supportsStateSync => true` comes last, once S1.7's tests and a manual RomM round trip pass: the global switch covers the emulator from that commit on (§5). Before it, the emulator already gets local states and Resume.
- **S1.6 Play screen.** With sync off: local states listed and resumable. With it on: States list, Resume (when supported), "state from another build" prompt (when a version is recorded). For sync-only emulators (no load-on-launch), decide whether the States list shows them unresumable; Y/Resume stays hidden.
- **S1.7 Tests** (the gate stays `flutter analyze && flutter test`):
  - `<emu>_state_sync_capable_test.dart`: matcher accepts/rejects (other game, undo, `.bak`, path separators, upper/lower case), `slotOf`, `looksLikeValidState` on real header bytes, `describeState` and screenshot on a fixture;
  - `<emu>_strategy_state_load_test.dart`: the exact load args;
  - the S0.2 profile test grows a case for the emulator;
  - `state_sync_gating_test` stays green (strategy and mixin agree). Change its PPSSPP "is false" expectation when PPSSPP lands.

### Stage 2: polish (optional)

- **Switch default.** Once S0.1 passes, consider making the global switch **on by default** for new profiles (existing profiles keep what they have). Before that, every emulator that reports `supportsStateSync` must have passed its manual check, since one switch now turns them all on. That is a product call; ask first.
- **Size.** PCSX2 and Dolphin Wii states run to tens of MB. Show sizes in the note under the switch ("PCSX2 states are about 30 MB each") and skip the upload of a state that didn't change. The hash already does this; confirm it in the log.
- **Retention.** RomM keeps every upload. The play screen folds older versions already; a "keep the newest N per slot on RomM" option could come later.

## 5. Risks

- **Emulator updates change state formats.** States from an older build may not load. DuckStation and PCSX2 record the format/version, and the play screen warns. Readers for the new emulators must record it too where the file has it, else the warning can't appear.
- **Same game, different dumps.** Matching by ROM stem (mGBA, Flycast, ares) misses a state from a PC whose file name differs. RomM's `fs_name` is the same on every PC that downloads through Gargosy, so this only affects imported ROMs. Accepted.
- **Wrong game key means wrong states.** A matcher that is too loose loads another game's state. Tests must cover "another game's state with a similar name".
- **One switch turns on every capable emulator.** An emulator whose state support is half done would sync as soon as it reports `supportsStateSync`. So an emulator sets it only after its S1.1 probe and S1.7 tests, and the manual pass in §6. Until then it may still be `StateSyncCapable` for local Resume (§2.1 needs only the mixin and load-on-launch), with `supportsStateSync` false. `state_sync_gating_test` must then allow "capable but not synced"; today it only checks that the flag implies the mixin, which still holds.
- **First launch on a new profile.** Each emulator's state folder must exist (or be creatable) before the first pull: add it to `EmulatorLayout.seed`. The pull writes through `PathGuard`, so the folder must be under the profile's `emulators\<id>`.

## 6. Done when

- S0.1–S0.5 are merged (one switch, states never in save zips, local Resume with sync off under test), and `docs/emulator-profiles.md` records a manual state-sync pass for DuckStation, PCSX2 and RetroArch.
- Each emulator in §3 that has been taken on has its probe row, its tests and a manual pass: a state made on PC/profile A is resumed on B.
