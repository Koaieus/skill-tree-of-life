---
name: swarm
description: Direct a team of parallel subagents through pre-planned, parallelizable work — one big issue split into file-disjoint units, or several small independent issues at once. Dispatch each unit to an isolated worktree agent, then review and fast-forward each branch into master. Use when the user says "swarm #<n>" / "swarm #<n>, #<m>", or asks to parallelize bulk/mechanical work across subagents. Only invoke as Opus, or as Sonnet when the plan is already written down.
---

# Swarm

One strong orchestrator, many fast workers. You do the thinking — decomposition,
review, merge. The workers do the typing, each in its own worktree, each with its
own context window.

The point is **context economy**. A swarm is worth running when the work would
otherwise fill your context with mechanical edits you don't need to remember. The
workers absorb that; you keep a lean session, so the user can still converse with
you while it runs.

> This is a **process** skill, and it is [`warp`](../warp/SKILL.md) with a fan-out.
> Read `warp`'s SKILL.md first — its rebase → `--ff-only` merge discipline applies
> here unchanged, once per worker branch, and is not repeated below. Read
> `.claude/rules/testing.md` too.

## Gate — do not swarm the wrong work

All four must hold. If any fails, use `warp` instead; a swarm on unsuitable work
costs *more* than doing it yourself, because you pay decomposition + N merges and
still end up reading the diffs.

1. **Pre-decided.** Every design question is already answered — in the issue, in a
   plan you just wrote, or in `docs/`. Workers cannot ask the user anything. An
   issue that floats alternatives ("…or some other way to show it") is *not* yet
   pre-decided: pick one, write it into the worker's prompt as settled, and tell
   the worker not to redesign it. Descope the issue's speculative asides ("maybe
   we can drop the trimming too?") to a `NOTES:` line — a second decision must not
   ride along on a bug fix. Pinning those forks is the orchestrator's job; needing
   the *user* to pin one is what fails this gate.
2. **Parallelizable into file-disjoint units.** See below. This is the hard one.
3. **Mechanical enough for a smaller model**, given red-green instructions: a
   failing test (or an exact spec) defines done.
4. **No human input mid-flight.** If the user must weigh in halfway, the swarm
   stalls with N worktrees open.

Being Opus is itself part of the gate. Sonnet may drive a swarm only when the
decomposition is already written down — not when it must be derived.

## The cycle

### 1. Resolve and plan

```bash
gh issue view <n> --comments        # once per issue
```

A swarm comes in two shapes, and they differ only in step 6:

- **One issue, N units.** Split it yourself onto disjoint files.
- **N independent issues, one unit each.** Small parallel issues; the partition
  comes free, since separate issues rarely share files. Verify that anyway — if
  two issues *do* overlap a file, they are not independent, and you run them
  sequentially or as one unit.

Then **think hard, before dispatching anything.** This is the step no worker can
do for you, and the step that decides whether the swarm succeeds. Produce, for
each unit: the files it owns, the acceptance test, and the exact instruction text.

Diagnosing the bug *before* you dispatch is usually worth it. A worker handed
"here is the root cause, implement exactly this" is a Sonnet doing mechanical
work — the thing this skill is for. A worker handed "figure out why edges render
above nodes" is a Sonnet doing the hard part alone, without your context.

### 2. Decompose onto disjoint files

**Two workers must never touch the same file.** Parallel edits to one file mean
the second rebase conflicts, and you've moved the work rather than saved it.

Partition by file, not by feature — features overlap, files don't. Write the file
list into each worker's prompt as an ownership boundary: *"you own exactly these
paths; if the task seems to need a file you don't own, stop and report it."*

Shared-file work (one `.tres` every unit must touch, a registry every unit
appends to) is **yours**. Do it in the main checkout before you dispatch, or as
an integration commit after you merge. Never hand it to two workers.

If the units don't come apart cleanly, that's a real answer: run `warp`.

### 3. Dispatch

**Claim every issue on the kanban before you spawn anything:**

```bash
mise gh-project -- status <n> in-progress    # once per issue, at dispatch
```

This is the *persistent* board (`mise gh-project`), not the in-session task list
of §3a — they are different surfaces and only this one survives the session. An
unclaimed issue looks free, so a later swarm (or the user) picks it up and
duplicates the work. Flip it back to `ready` if you dispatch nothing.

Spawn every worker **in a single message** — that is what makes them run in
parallel. Per `Agent` call:

- `isolation: "worktree"` — mandatory. Without it, background workers edit the
  shared main checkout and collide with each other and with the user's WIP.
- `model: "sonnet"`, or `"haiku"` for ultra-mechanical work (rename, mass
  string-replace, boilerplate).
- `run_in_background: true`.
- The prompt must open with: **"Invoke the `drone` skill, then do the following."**
  `drone` carries the flow rules so you don't restate them N times. (Subagents do
  inherit the skill list — verified. If one ever reports it can't find `drone`,
  tell it to `Read .claude/skills/drone/SKILL.md` instead; it's plain markdown.)

Each `Agent` result hands back `worktreeBranch` and `worktreePath`. Record them —
they are your merge handles, and they're the only way back to a worker's commits.

Give each worker its acceptance test up front. A worker that can run
`mise run test:one -- res://test/unit/test_foo.gd` and see green knows it is done;
one that can't will report "looks right" and be wrong.

### 3a. Teammates & a shared task board (preferred coordination surface)

Spawn workers as **teammates** rather than fire-and-forget subagents. A teammate
is spawned via the `Agent` tool's `name` parameter and joins the session's
implicit **agent team** — which gives two things a bare background subagent does
not: a shared **task list** (`TaskCreate` / `TaskList` / `TaskUpdate`) and a
mailbox (`SendMessage`). The task board is the coordination surface — you see
each unit's status flip live instead of blocking on final reports, and the board
*is* the shared plan the user asked to see.

**Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`** read at launch (env var, or
an `env` block in `settings.json` — the durable home, since it applies regardless
of cwd/shell). Check it first — `echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. When
it's unset the `name` parameter is inert: workers spawn isolated, cannot see the
task board, and report only via their final message. You cannot enable it
mid-session; it's a relaunch. If it's off and the user wants teammates, say so and
let them relaunch — don't seed a board that the workers will never see (see the
gotcha below).

**Launch-timing trap:** the `echo` reads your Bash shell, not the running
Claude process. If the user adds the flag mid-session, a fresh Bash shows `1`
while the session that decided team-membership at *its* startup still has teams
off. So a value that flipped `unset → 1` partway through the session is **not**
proof teams is live — confirm with a relaunch before seeding a board you're
betting the swarm on.

Flow when teams is on:

1. **Seed the board before dispatch.** One `TaskCreate` per unit; put the
   ownership boundary (the exact paths it owns) and the acceptance test right in
   the `description`. Any shared-file integration step you own becomes its own
   task, with `addBlockedBy` naming the unit tasks that must land first — the
   dependency is now explicit on the board instead of living only in your head.
2. **Spawn with `name`.** Still `isolation: "worktree"`, `model: "sonnet"` (or
   `"haiku"`), `run_in_background: true`. Give each teammate a stable `name`
   (`field-noise`, `field-gaussian`) and tell it in its prompt **which task id it
   owns** and to `TaskUpdate` it: `in_progress` on start, `completed` only on
   green. `drone` still governs its flow.
3. **Watch, don't poll narratively.** `TaskList` shows the live board. A teammate
   stuck on a blocker is unblocked by `SendMessage` to its name — worktree and
   context intact, far cheaper than a cold respawn (same as the Collect rule).

Gotchas:

- **The board is team-scoped.** Tasks are shared only among teammates on the same
  team. Seed a board, then spawn plain (nameless / teams-off) subagents, and they
  won't see it — you've built a plan nobody reads. Board and teammates go together
  or not at all.
- **A teammate still cannot see this conversation.** The task `description` is its
  briefing — everything the fire-and-forget prompt would carry (owned files,
  acceptance test, "done" definition) goes there or in the spawn prompt, not left
  implicit because "it's on the board."
- Teardown, review, and merge (steps 5–7) are unchanged — a teammate's worktree
  and branch behave exactly like a background worker's.

### 4. Collect

`drone` mandates a terse structured report. Read those, not the diffs. If a
worker's report is a wall of text, that's a `drone` violation — don't propagate
it into your summary to the user.

A worker that reports a blocker (needed a file it didn't own; test won't go green;
ambiguity in the spec) has done the right thing. Resolve it yourself, or re-dispatch
with `SendMessage` to that agent id — its worktree and context are still alive, and
continuing it is far cheaper than a cold respawn.

### 5. Review

You are the reviewer. The workers are smaller models and had no advisor.

```bash
git diff master...<worktreeBranch> --stat     # shape first
git diff master...<worktreeBranch>            # then read it
```

Verify the ownership boundary actually held (`--stat` shows any file a worker
shouldn't have touched) before you look at content. Nothing merges unreviewed.

A green suite proves the worker's *mechanism*, not the *outcome*. That gap is
widest on visual work: a z-index assertion fully determines draw order, but no
assertion tells you a semitransparent band is legible on screen, and a shader
that compiles can still render nothing. When a unit changes what the game looks
like, either drive it (`mise run play`, `/verify`) or say plainly to the user
that you confirmed the plumbing and not the pixels. Don't let "tests pass, shader
compiles" quietly stand in for "it looks right."

### 6. Merge, one branch at a time

Per branch, in sequence, exactly as `warp` step 6 describes: rebase the branch
onto `master` from inside its worktree, then fast-forward `master`. Sequential is
not a limitation — each rebase re-tests the *next* branch against the merged
result of the previous ones, which is the only place a cross-unit break surfaces.

Run `mise run test` after each merge, not only after the last. When something
breaks, you want to know which branch did it.

If the units were file-disjoint, every rebase is clean. A conflict here means the
decomposition leaked — fix the decomposition's consequence, not just the conflict.

**Closing the issue(s).** Workers never write `Closes #<n>` themselves — you add
it, because only you know which branch is last. Amend it on before that branch's
rebase, while you're still upstream of the merge:

- **One issue, N units** — one `Closes #<n>`, on your integration commit, or
  amended onto the *final* branch's tip. Not on the others: whichever merged
  first would close the issue while the rest of the work is still in flight.
- **N independent issues** — one `Closes #<n>` per branch, each naming its own
  issue. Every branch is the last one for its issue.

`Closes` fires on **push**, not on the local fast-forward. So merging does not
close anything. Check `git status -sb` before you claim an issue is done, and
remember `master` may carry unrelated commits (yours, or another agent's) that a
push would ship alongside your work — surface that and let the user decide.

Because the close is deferred to the push, move the issue on the kanban as each
one lands, so the board reflects reality even though the issue is still open:

```bash
mise gh-project -- status <n> in-review     # branch landed on master, awaiting push
```

If a worker reported a blocker and stopped, put the issue back to `ready` (or
`backlog`) with a comment saying what blocked it — never leave it `in-progress`
with nobody on it. A stuck `in-progress` is the one state that silently blocks
the next swarm.

### 7. Teardown

An `isolation: "worktree"` worktree is auto-removed only if the worker left it
unchanged — which is exactly the workers you *don't* need to clean up after.
Every worker that committed leaves one behind:

```bash
git worktree list                                   # find the survivors
git worktree remove .claude/worktrees/agent-<id>
git branch -d worktree-agent-<id>                   # -d, not -D: refuses if unmerged
```

Both plain forms work on a merged worker branch — reach for `--force` / `-D` only
once you know why the plain one refused. `remove` refuses while the worktree is
still `locked` (the agent hasn't exited) or dirty; `branch -d` refuses when the
branch isn't in `master`, which means you dropped a worker's work. Neither is a
formality to `--force` past.

## Gotchas

- **Worker worktrees live under `.claude/worktrees/agent-<id>/`, on branch
  `worktree-agent-<id>`** — not under `.worktrees/`, and not from
  `mise run worktree:new`. The harness creates them, branched from `master`'s tip
  at spawn time, and returns the path and branch in the tool result. That's the
  substrate; `mise`'s worktree tasks are for `warp`'s single-checkout cycle.
- **Workers branch from `master` as it was when they spawned.** Merging branch A
  moves `master`; branch B is now behind. That's why step 6 rebases each branch
  immediately before its own merge, not all of them up front.
- **Don't let a worker call `advisor`.** You are the advisor — you're the larger
  model and you hold the plan. `drone` tells them this; don't undercut it by
  suggesting it in a worker prompt.
- **A worker's context is not yours.** It cannot see this conversation, the issue,
  or the sibling workers' units. Everything it needs goes in its prompt: the
  files it owns, the acceptance test, and what "done" means.
- **Relay, don't paste.** The whole point is your context stays small. Summarize
  worker reports for the user in your own words; a swarm whose orchestrator pastes
  N diffs has spent its context anyway and saved nothing.
- **Always `git -C <path>`, never bare `git` after a `cd`.** Bash's working
  directory persists across tool calls. `cd` into a worktree to run its tests and
  every later `git` command silently targets *that* worktree — a `merge --ff-only`
  aimed at master will cheerfully report "Already up to date" while merging a
  branch into itself. Nothing errors. Spell out the repo path on every git call.
- **A worker's fresh worktree cold-imports and dirties tracked `.import` files**,
  which makes `git rebase` refuse with "cannot rebase: You have unstaged changes."
  Run `git -C <worktree> checkout -- .` first. Same for the main checkout after a
  real-backend (`opengl3`) shader check — it re-imports every texture.
- **`master` can move under you mid-swarm.** Another agent may land commits in the
  shared main checkout while your workers run. That's fine — it's why step 6
  rebases each branch immediately before its own merge — but *re-read `master`*
  before concluding a merge misbehaved.
- **Untracked files in the main checkout are invisible to worktrees**, so a test
  count taken there won't match a worker's. Compare tracked-only totals, and when
  a count is off, `git ls-files --error-unmatch <path>` before suspecting a worker.
  A file present in the main checkout's suite but absent from every worktree's is
  almost certainly untracked, not deleted by a worker.
