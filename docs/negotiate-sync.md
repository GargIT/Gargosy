# RomM's negotiate sync: why Gargosy doesn't use it (yet)

Decision of 2026-11-07 for #289. RomM 5.4 offers a sync protocol
(`POST /api/sync/negotiate`, then `POST /api/sync/sessions/{id}/complete`)
in which the server decides, save by save, whether a device uploads,
downloads, deletes, has a conflict or has nothing to do. Gargosy keeps its
own sync and parks the move. Two small steps go in 0.10.0: exact per-device
records (#293) and a shadow call that only logs (#294).

## How RomM decides

From `backend/handler/sync/comparison.py` and `backend/endpoints/sync/__init__.py`
(5.4). Saves pair on **(rom_id, slot)**, the newest server save of the slot.

1. The same hash on both sides: `no_op`.
2. The client holds a version the server removed (RomM keeps a deletion
   log): `download`, or `delete` when the slot is now empty.
3. The device synced the save before: a side changed when its time is after
   `last_synced_at` *and* its hash isn't the one recorded then
   (`last_sync_hash` for the device, `last_sync_server_hash` for RomM). Both
   changed: `conflict`; one: `upload` or `download`; neither: `no_op`.
4. No history: the newer timestamp wins; the same time with different
   hashes is a `conflict`.

A server save the client didn't list is skipped when the device synced it
and it hasn't changed since (RomM reads that as deleted on the device),
unless the client sends `restore_unlisted`; otherwise it's a `download`.
`emulators: [...]` limits pairing to saves those emulators wrote; a `null`
slot is never paired. `conflict` comes with no resolution.

## How Gargosy decides

- **Pull** (`SaveSyncService._devicePullSave`): RomM's newest save of the
  game, whichever slot and emulator; kept when the local save is newer,
  skipped when it's the same by RomM's hash (`_alreadyHave`). RomM's
  `is_current` is not trusted to skip a pull, so a save deleted on this PC
  comes back (#94).
- **Push**: a stored hash says nothing changed; RomM's `409` becomes
  `SaveConflictException` and the play screen's prompts.
- A save made by another emulator can be converted (the save catalog), so a
  game goes on in another emulator.

## Where the two don't fit

1. **Pairing ignores the emulator.** Gargosy puts every emulator's save of a
   game in one slot (`gargosy`, or `autosave` for sigil's units). Under
   negotiate, two emulators' saves of a game are one slot and the newer
   wins. `emulators: [current]` keeps them apart, but then going on in
   another emulator needs Gargosy's own catalog anyway.
2. **A save deleted on this PC.** Gargosy brings it back from RomM; negotiate
   by default calls it deleted on the device and stays quiet.
   `restore_unlisted: true`, scoped to the game, keeps Gargosy's behaviour.
3. **Exact baselines.** Emulators rewrite save files at start and exit, so
   times move without a change; negotiate stays calm only when the device's
   hash matches its baseline. That needs a baseline after every pull (#293)
   and the same hash RomM computes for the upload (done for files and
   bundles; sigil's units would need a collect before launch just to hash).
4. **Clocks.** The PC's file times are compared with times RomM wrote. A PC
   clock ahead of the server reads as local changes; only exact hashes
   neutralise it.
5. **`delete` is new.** A save deleted on RomM (the web page, another
   device) would be deleted here. Gargosy has the machinery
   (`deleteLocalSave`: backup to `backups\deleted\`, card edits), but it's
   the riskiest new behaviour.
6. **A shared device.** Profiles of one RomM user signed in by password
   registered as one RomM device and shared its records (#293 fixes it).
7. Save states, other players' saves and screenshots aren't part of it.

## Why it's parked

- **No bug to fix.** Gargosy's sync handles every case met so far (#94, the
  `is_current` distrust, conflicts, conversions). The move would replace
  working code with RomM's version of it.
- **Large and risky.** Every save shape (single files, bundles, sigil's
  units, cards, folder saves) has to fit RomM's model, in the code where a
  mistake loses a save.
- **It costs what works now**: going on in another emulator, or a workaround
  to keep it.
- **The one new thing**, deletions on RomM reaching the PC, is also the
  riskiest and few need it.

## What goes in instead (0.10.0)

- **#293:** a device hash after every pull, and one RomM device per profile:
  RomM's per-device records are right today and ready for negotiate.
- **#294, shadow negotiate:** before a game's pull and push, the same call
  RomM's clients make, for that game only, logged as `[Negotiate]` lines next
  to what Gargosy did; nothing changes. The logs say whether negotiate would
  ever decide better.

## Reading the shadow's logs (#294)

Each `[Negotiate]` line is RomM's answer for one game next to what Gargosy
did. Its limits:

- It's skipped when a save operation runs or waits (the upload queue, a
  push), so it never holds a launch or a push up; a gap in the logs is that.
- The question goes out just before Gargosy's own pull or push. RomM
  usually answers first, but if Gargosy's download or upload reaches RomM
  before it, RomM answers from the state after Gargosy's change.
- `file_size_bytes` is the files' own size; a bundle uploads as a zip, so
  RomM's size differs. RomM doesn't decide by size.
- At exit the save is gathered and hashed once for the shadow and again for
  the push.
- "nothing pushed" covers both no save to upload and a failed push.

## When to look again

- Shadow logs show RomM deciding better than Gargosy (a conflict Gargosy
  missed, a pull it shouldn't have made).
- Players want deletions on RomM to reach their PCs.
- RomM's other clients (Argosy, Grout) and Gargosy disagree about the same
  save in practice.

Then, in steps: let negotiate drive `download`/`upload`/`no_op` with
`conflict` on Gargosy's prompts, `delete` behind a setting and always backed
up, today's path kept for a RomM before 5.4; drop Gargosy's own decisions
once the logs agree.
