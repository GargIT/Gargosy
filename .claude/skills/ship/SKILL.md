---
name: ship
description: Take the current Gargosy branch from finished code to a merged PR - gate, docs check, push, PR from the template, dev install for hand tests, green CI, merge.
disable-model-invocation: true
---

# Ship the current branch

Run these steps in order. Stop and report at the first failure; don't skip a step.

## 1. Branch

- Never ship from `main`. If on `main`, make a branch `claude/<issue>-<short-name>` first.
- Find the issue number from the branch name or the commits. Read the issue with `gh issue view <n>`.

## 2. Gate

```
dart format lib test tool && flutter analyze && flutter test
```

On a fresh checkout, run `powershell -File tool/build_sigil.ps1` first.
Fix every failure and run the gate again. Report the test count from the output.

## 3. Docs check (from `git diff main...HEAD --stat`)

- **CLAUDE.md file map:** every file created, split or moved is listed. Use the `file-map-keeper` agent.
- **CHANGELOG.md:** a line under `[Unreleased]` if a user would notice the change.
- **`docs/hand-tests.md`:** numbered `[ ]` rows for whatever only a person can try.
- **Rules:** run the `rules-reviewer` agent on the diff, and fix what it confirms.

## 4. Commit and push

- **Commits:** Conventional Commits with the issue number, e.g. `feat: … (#145)`.
- **No session link:** never put a `claude.ai/code/session_…` link in a commit or PR. The guard hook blocks it.
- **Push:** `git push -u origin HEAD`.

## 5. PR

- **Template:** fill in `.github/pull_request_template.md`. Keep every section: Closes, What changes, Not in this PR, Tests, Checklist.
- **Checklist:** tick only what was checked.
- **Create:** `gh pr create --base main --title "<type>: <summary> (#<issue>)" --body-file <file>`.

## 6. Hand-test install

Right after the push, install the branch for the user's hand tests:

```
pwsh tool/make_dev_release.ps1
```

It refuses if Gargosy is running from `C:\Retro\apps\gargosy`. If it does, ask the user to close Gargosy, then run it again.
Tell the user which hand-test rows (numbers) to try.

## 7. CI, review, merge

1. Wait for CI: `gh pr checks <pr> --watch`.
2. If CI fails, fix it, push again, and keep waiting.
3. Review the PR diff with the `code-review` skill and fix what it confirms.
4. Once the review is clean and CI is green, merge it:

   ```
   gh pr merge <pr> --merge --delete-branch
   ```
5. If the issue's hand tests are still open, leave the issue open and say which rows are waiting. Otherwise it closes through `Closes #`.
