---
name: warp
description: Drive a full trunk-based issue cycle in an isolated git worktree — resolve a GitHub issue (by number or free-text query), spin up a worktree, implement, test, present for approval, fast-forward master, close the issue via commit message, and tear down. Use when the user says "warp #<n>", "warp this issue", "use warp to implement...", or asks for an isolated worktree-based implementation cycle instead of working directly on the current checkout.
---

# Warp

Drive one issue from ticket to merged, on an isolated `git worktree` instead
of the current checkout — the main checkout is a shared surface where other
agents may hold uncommitted WIP. Warp gives each issue its own disposable
checkout, advances `master` only by **fast-forward** — never by switching the
main checkout's own branch or stashing its WIP — and gates the merge on
explicit user approval. Rebase the worktree branch onto `master` first, so
the merge is always a pure fast-forward that leaves any unrelated WIP in the
main checkout untouched. Why each rule below exists: `docs/charters/warp.md`.

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

**2.5. Claim the issue on the kanban board**
```bash
mise gh-project -- status <n> in-progress
```
(Project is linked to the repo — issues appear automatically.)
Move the issue out of Backlog/Ready so other agents don't pick it up.

**3a. Decide the test, and make it red first**

Before writing the fix, answer one question: **does this change earn a test?**
Done is *"a failing test to make green, or an exact behavioural spec"* — and the
second half is the right answer for visual/tuning/refactor work, not a cop-out.
If the issue went through `swarmify`, its `## Acceptance spec` already names the
test; use that one.

If it earns a test, write it **before** the implementation and watch it fail —
red→green, never test-after. A test written against already-working code proves
nothing about the bug it was supposed to pin. The repo-specific catch: a new
test file referencing a `class_name` or method you haven't written yet is a
**parse error, not a red test**, and GUT silently skips it while reporting the
suite green. So stub the seam first, `mise run refresh` if the `class_name` is
new, then confirm `test:one` actually *ran* your file and failed on *your*
assert line. Full story, including when to skip tests entirely:
**`docs/domain/red-green.md`**.

**Before writing that test, list what its setup has to reach into.** A test
of X that must write another unit's internals (`y.state.foo`, `y._flag`, a
visual's `modulate.a`) to arrange X's state has found a seam, not a fixture:
the fact belongs to Y. Three questions, answered from the plan before any
code exists — *who owns this fact? is this one thing pretending to be N? what
does it cost per frame / at scale?* — and the fix goes into the owner (or
gets filed against it), never into the unit that shows the symptom. The test
setup is the cheapest detector of coupling this repo has.

**3b. Implement**
Same repo, same rules — `.claude/rules/*` apply unchanged inside a worktree.
Two things specific to running in a *fresh* worktree:
- It has no `.godot/` yet (gitignored, per-checkout). The first
  `godot --headless --editor ...` invocation cold-imports — budget a few
  seconds before the first `mise run check`/`test` call returns. Its
  `.godot/` is fully independent of the main checkout's, and it reproduces
  the exact same "harmless during cold boot" script-error noise as a plain
  fresh clone at the same commit — not a worktree-specific issue.
- If you introduce or rename a `class_name`, the worktree needs its own cache
  refresh (`mise run refresh`) — the main checkout's refresh doesn't propagate.

**4. Confirm before presenting anything**

Step 3a already gave you a green `test:one`. This step widens that to the suite.
The full suite is a **gate**, not a feedback loop (its current cost is in
`CLAUDE.md`), so reach for it **once**, right before step 5. While iterating,
use the cheap ladder instead:

```bash
mise run check                                     # ~20s — after every script edit
mise run test:one -- res://test/unit/test_foo.gd   # the file you're changing
mise run test:dir -- res://test/unit/<subsystem>/  # its subsystem, once you believe you're green
mise run test                                      # full suite — ONCE, right before step 5
```

Don't skip the full run to save time — the approval step in #5 assumes tests
already pass; surfacing red tests at approval time wastes the review. But
don't re-run it mid-iteration either — that's what `test:one`/`test:dir` are
for, and a full-suite round trip on every edit is exactly the waste this
ladder exists to avoid.

**5. Pending approval — stop and ask**
Present the diff/summary to the user. **Do not merge without explicit
go-ahead.** This is the same "risky action" confirmation the top-level agent
instructions already require for anything touching shared state (`master`
counts) — warp doesn't get a special exemption just because the work
happened off to the side in a worktree.

**6. Land — one command, always a fast-forward, never touching the main checkout's WIP**

Only after the go-ahead of step 5. From anywhere in the checkout:
```bash
mise run land -- issue-<n>-<slug> --closes <n>
```
That is the whole merge step. `land` takes an exclusive lock (a second
landing waits and says so — not a hang), rebases your branch onto `master`
*inside your worktree*, runs `mise run check` plus `mise run test:dir` for
every `test/unit/<dir>/` the branch touches on the rebased tree (a rebased
tree is a tree nobody tested), amends `Closes #<n>` onto the tip if your
message lacks it (so the tested sha is the landed sha), fast-forwards
`master` in place, and moves the board card to in-review. It never runs the
full suite and never pushes. Protocol details: `.mise/tasks/land`.

**A refusal is signal, not an obstacle.** Each non-zero exit names one cause;
each has one answer — read the reason, do that, run `land` again:

- *no such branch* / *checked out in the main checkout* — `land` lands
  worktree branches only; check the name.
- *main checkout is on '<x>', not master* — the one case `land` refuses by
  design. Don't switch it. Rebase by hand inside the worktree (`git rebase
  master`), then advance the ref without a checkout:
  `git fetch . issue-<n>-<slug>:master` (ff-only by default) — or ask the
  user.
- *main checkout has uncommitted changes to files the branch also changes* —
  someone's live WIP overlaps yours; surface it to the user, never force
  past it. (Unrelated dirty files are fine; `land` proceeds and says so.)
- *the branch's worktree has uncommitted changes* — commit them first.
- *rebase … conflicts in: <files>* — a real overlap; the rebase was aborted
  and your branch is untouched. Resolve in the worktree, re-test, commit,
  land again.
- red `check` / `test:dir` — the verdict lines say what; fix in the
  worktree, land again.
- *master could not fast-forward* — `master` moved under the rebase; land
  again.

Never `--force`, never a `+refspec`, never `--no-ff`, never `git checkout
master` / `git stash` / a `_merge` worktree to route around any of these.

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

No silent long-lived divergence.

## Gotchas

- **Never `git checkout` or `git stash` in the main checkout to land.** The
  main checkout may have someone else's uncommitted WIP (documented in
  `CLAUDE.md` → the multi-agent caveat). `land` never touches it: a
  fast-forward leaves unrelated dirty files alone and refuses only on a real
  overlap, and a main checkout parked on another branch is handled by
  `git fetch . <branch>:master` (step 6), not by switching it. No merge
  worktree, no stash.
- **`git worktree add` from a dirty main checkout is safe** — it doesn't
  touch the working tree, only reads `HEAD`. Don't `git stash` or otherwise
  disturb the main checkout's working directory to make room for a worktree.
- **`.worktrees/` is gitignored** (`.gitignore`) — don't add worktree
  contents to commits; they're disposable by design.
