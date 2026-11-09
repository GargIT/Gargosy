# End-to-end tests against a real RomM

Every other test fakes RomM (`test/helpers/fake_dio_adapter.dart`). The tests
in `test/e2e/` (#242) send Gargosy's own RomM calls to a real RomM. They show
when RomM changes something Gargosy relies on.

They cover:

- signing in with a password (a client token);
- platforms, a gallery page with its A–Z index, a game;
- downloading a game, checked against RomM's hashes;
- uploading a save and pulling it back;
- uploading a state, labelling it and pulling it back;
- making, renaming, sharing and deleting a collection;
- sending a play session and reading it back.

With an admin login they also cover:

- the admin's rights, and that a viewer has none of the admin tools;
- a scan of one platform, followed until it ends;
- uploading a game in pieces, which a scan adds; then deleting it.

They are tagged `e2e`. Without `ROMM_E2E_URL` they are skipped, so a normal
`flutter test` passes without a RomM.

## On CI

`.github/workflows/e2e.yml` runs them on Linux, in two jobs:

- RomM 5.4.1, the version Gargosy is pinned to. It must pass.
- RomM's newest (`latest`). A failure there doesn't hold a PR.

They run on every PR, on `main`, and every Monday.

`tool/e2e/start_romm.sh` sets up the RomM:

1. It writes a test library with `make_roms.py`: three small made-up ROM
   files, two Game Boy and one NES. No real game is copied.
2. It starts RomM and MariaDB with `tool/e2e/docker-compose.yml`.
3. It makes two users: `gargosy-admin` (admin) and `gargosy-player` (viewer).
4. It runs the first scan, then prints the `ROMM_E2E_*` values.

You can run it yourself on a Linux machine or in WSL with Docker:

```
bash tool/e2e/start_romm.sh            # RomM 5.4.1
ROMM_VERSION=latest bash tool/e2e/start_romm.sh
```

Set the printed values in your shell and run the tests. When you are done,
remove the RomM with `bash tool/e2e/start_romm.sh down`.

## Against your own RomM

The same tests run against any RomM 5.4 or newer. They write to it, so prepare
it first:

1. **Make a test user** with the viewer role. Never use your own user: the
   tests upload and delete saves, states, collections and play sessions.
2. **Make a test platform** with one or two small ROMs, such as homebrew. The
   tests download the smallest game of the platform.
3. **Optional: use an admin user** for the admin tests. They scan the test
   platform, then upload a 10 MB file named `Gargosy E2E Upload <time>` to it
   and delete it again, from RomM's disk too. Without an admin user these
   tests are skipped.

Then set these variables and run the tests (PowerShell):

```
$env:ROMM_E2E_URL = 'https://romm.example.com'
$env:ROMM_E2E_USER = 'gargosy-test'
$env:ROMM_E2E_PASSWORD = '…'
$env:ROMM_E2E_PLATFORM = 'gb'             # the test platform's slug (gb by default)
$env:ROMM_E2E_ADMIN_USER = '…'            # optional
$env:ROMM_E2E_ADMIN_PASSWORD = '…'        # optional
flutter test --tags e2e test/e2e
```

Each test deletes what it made, even when it fails. Every name it gives
starts with `Gargosy E2E`, so you can find anything a stopped run left
behind. Each sign-in makes a client token, which is deleted at the end; a
stopped run leaves its token in the user's Client tokens. A RomM with a
self-signed certificate isn't supported.

Don't set these variables in GitHub's secrets: the CI tests run against
their own RomM.
