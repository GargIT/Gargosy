# Security

## Reporting a problem

Please don't report security problems in a public issue. Instead, either:

- open a private report under this repository's **Security** tab →
  **Report a vulnerability**, or
- mail **gargosy@gargit.se**.

Say which Gargosy version and which Windows version you use, what happens,
and how to make it happen. Only the latest release gets security fixes.

Gargosy is a hobby project: you'll get an answer as soon as I can manage, but
there is no promised response time.

## What counts

- RomM logins or tokens leaking out of a profile, or readable by another
  Windows user.
- A RomM server, a game or save file name, or a downloaded archive making
  Gargosy write outside its own folder.
- A download or archive making Gargosy run something it shouldn't.
- Certificates: a self-signed certificate trusted for more than the
  profile's own RomM server.

## What doesn't

- The profile PIN. It's a family lock, not security: anyone using the same
  Windows account can open the Gargosy folder.
- Problems in RomM or in the emulators themselves: please report those to
  their projects.
