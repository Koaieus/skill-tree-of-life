---
name: warp
description: Drive a full trunk-based issue cycle in an isolated git worktree — resolve a GitHub issue (by number or free-text query), spin up a worktree, implement, test, present for approval, merge back to master, close the issue via commit message, and tear down. Use when the user says "warp #<n>", "warp this issue", "use warp to implement...", or asks for an isolated worktree-based implementation cycle instead of working directly on the current checkout.
---

# Warp

Drive one issue from ticket to merged, on an isolated `git worktree` instead
of the current checkout. This exists because this repo has set up worktree DX
— parallel agents editing the same checkout directly, occasionally colliding
on someone else's WIP. Warp gives each issue its own disposable checkout,
touches `master` only via a short-lived merge worktree (never by switching
the main checkout's own branch), and gates the merge on explicit user approval.

> This is a **process** skill. It orchestrates existing tools — `gh`, the
> `mise run worktree:*` tasks (`mise.toml`), and the project's own testing/
> workflow rules (`.claude/rules/testing.md`, `.claude/rules/godot-workflow.md`)
> — it does not replace any of them. Read those before starting; warp does
> not repeat their content here.

## Read first

```
mise.toml                          # worktree:new / worktree:ls / worktree:rm tasks
.claude/rules/testing.md           # how to run GUT tests (mise run test / test:one / test:dir)
```

## The cycle

**1. Resolve the issue**
```bash
gh issue view <n>
```
If the user gave a free-text query instead of a number, `gh issue list` and
match, or ask them to confirm the number — don't guess silently. Read the
full body including any triage comments; they often narrow scope more than
the title does.

**2. Create the worktree**
```bash
mise run worktree:new -- <n>
```
This fetches the issue title, slugifies it, creates `.worktrees/issue-<n>-<slug>/`
on a new branch of the same name, and prints the `cd` path. `cd` into it —
**all implementation work happens inside the worktree**, never in the main
checkout.

**3. Implement**
Same repo, same rules — `.claude/rules/*` apply unchanged inside a worktree.
Two things specific to running in a *fresh* worktree:
- It has no `.godot/` yet (gitignored, per-checkout). The first
  `godot --headless --editor ...` invocation cold-imports — budget a few
  seconds before the first `mise run check`/`test` call returns. Confirmed
  empirically during #86: this does not touch or corrupt the main checkout's
  `.godot/` (fully independent), and reproduces the exact same "harmless
  during cold boot" script-error noise as a plain fresh clone at the same
  commit — not a worktree-specific issue.
- If you introduce or rename a `class_name`, the worktree needs its own cache
  refresh (`godot --headless --editor --quit`) — the main checkout's refresh
  doesn't propagate.

**4. Test before presenting anything**
```bash
mise run test              # inside the worktree
mise run check              # if any class_name changed
```
Don't skip this to save time — the approval step in #5 assumes tests already
pass; surfacing red tests at approval time wastes the review.

> **`mise run check` is currently red repo-wide** (60 `SCRIPT ERROR`s from a
> `CoreHealthBar` placeholder-binding issue, confirmed during #86 to
> reproduce identically in a clean clone — likely #94, not your regression).
> Compare your worktree's `check` output against a baseline clean-clone run
> before concluding *you* broke something; don't chase this pre-existing
> failure inside an unrelated warp cycle.

**5. Pending approval — stop and ask**
Present the diff/summary to the user. **Do not merge without explicit
go-ahead.** This is the same "risky action" confirmation the top-level agent
instructions already require for anything touching shared state (`master`
counts) — warp doesn't get a special exemption just because the work
happened off to the side in a worktree.

**6. Merge back to master — via a dedicated merge worktree, never the main checkout**
The main checkout may have someone else's uncommitted WIP on some other
branch (see Gotchas) — if dirty: never `git checkout master` there to merge.
If master has progressed, rebase your worktree on the tip, make sure the incoming
changes play nice.
If master is clean, simply merge and get it over with.
If master is dirty, git stash - merge - pop stash. The merge shouldn't conflict,
the stash pop may but that's now the main tree's problem.
Prefer fast-forward / rebase over a merge commit — the issue's own framing is
"trunk-based, one main branch, rebase often." Commit message must contain
`Closes #<n>` (see `CLAUDE.md` → Git) so GitHub auto-closes the issue.
The main checkout's own `HEAD` doesn't _need_ to move but ideally it does and gets
all the latest additions on there sooner rather than later.

**7. Teardown**
```bash
mise run worktree:rm -- <n>
```
Confirms before deleting the branch (keeps it if you decline) — see the task
definition in `mise.toml` if you need the exact fuzzy-match behavior.

## EOD fallback (if not done by end of day)

Don't let a warp branch silently drift for days. Pick one:

- **(a) Merge back partial-but-functional.** Comment out the incomplete
  piece with a `# TODO(#<n>): <what's missing>` pointing at the still-open
  issue, so `master` stays runnable, then merge + teardown as normal (issue
  stays open — only close via `Closes #n` when it's actually done).
- **(b) Keep the branch alive, rebase it onto `master` often.** Acceptable
  for genuinely multi-day work, but don't let it go stale — rebase at least
  once a day so it doesn't accumulate a painful conflict at merge time.

No silent long-lived divergence — that's the exact failure mode #86 exists to
prevent.

## Gotchas

- **Never `git checkout` in the main checkout to merge.** The main checkout
  may have someone else's uncommitted WIP on some other branch (documented
  in `CLAUDE.md` → "No worktrees" / the multi-agent caveat) — this is not
  hypothetical, it happened mid-session during #86 itself. Merging always
  goes through the disposable `.worktrees/_merge` worktree from step 6, never
  by switching the main checkout's own branch.
- **`git worktree add` from a dirty main checkout is safe** — it doesn't
  touch the working tree, only reads `HEAD`. Don't `git stash` or otherwise
  disturb the main checkout's working directory to make room for a worktree.
- **`.worktrees/` is gitignored** (`.gitignore`) — don't add worktree
  contents to commits; they're disposable by design.
