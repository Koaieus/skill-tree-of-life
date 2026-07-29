---
name: swarm
description: Direct a team of parallel subagents through pre-planned, parallelizable work — one big issue split into units, or several small issues at once. Hold the dependency graph, dispatch each unit to an isolated worktree agent in waves, then review and fast-forward each branch into master yourself. Use when the user says "swarm #<n>" / "swarm #<n>, #<m>", or asks to parallelize bulk/mechanical work across subagents. Only invoke as Opus, or as Sonnet when the plan is already written down.
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
2. **Decomposable into units a worker can hold.** Prefer file-disjoint units —
   they parallelize with clean rebases. But overlap is a **sequencing** fact, not
   a disqualification: two units on one file run in order, and a unit blocked on
   another can ride the same swarm behind it. Maintaining that DAG is your job
   (see below). What fails this gate is work that won't come apart at all.
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

### 2. Decompose, and own the DAG

**Two workers must never touch the same file *at the same time*.** Parallel edits
to one file mean the second rebase conflicts, and you've moved the work rather
than saved it.

The fix is **sequencing, not exclusion.** Overlapping units are legitimate work —
dispatch them in waves: wave 1 goes out in parallel, you review and merge it,
then wave 2 dispatches from the new `master` tip. A unit that *blocks* another
belongs in the same swarm, one wave ahead of it. Holding the dependency graph and
deciding those waves is the orchestrator's core job; nobody upstream of you
should be distorting an issue's scope to keep files apart.

Write each worker's file list into its prompt as an ownership boundary: *"you own
exactly these paths; if the task seems to need a file you don't own, stop and
report it."* Within a wave that boundary is absolute.

Shared-file work (one `.tres` every unit must touch, a registry every unit
appends to) is **yours**. Do it in the main checkout before you dispatch, or as
an integration commit after you merge. Never hand it to two workers in one wave.

**Find the shared contract before you dispatch, and commit it first.** N units
implementing "the same kind of thing" almost always need one seam none of them
owns — a base-class method they all override, a registration call, a way to say
"I have nothing to show". Left undiscovered, each worker invents its own and none
of them merge cleanly. Grep for the *consumer* of the units' output and see what
it actually calls; that is where the seam hides. Write it, test it, commit it to
`master`, and only then spawn — workers branch from the tip, so a seam committed
after dispatch is invisible to them.

**Pre-flight the units' envelopes against real content.** A stub sized for
placeholder text is not evidence the real thing fits. One unit in this run was
blocked at the finish line because its panel's authored size had only ever held
five dummy labels, and growing it collided with positions authored in files no
content unit was allowed to touch. That was foreseeable in one minute of looking
before dispatch, and cost a full escalation round afterwards. When units fill a
layout you own, check the worst-case content fits *first*.

If the work won't come apart into units at all, that's a real answer: run `warp`.

### The merge contract — never make a deep-context drone merge

A drone **commits inside its own worktree and stops** (`drone` mandates exactly
this: commit before reporting, never rebase, never merge, never touch `master`).
Its commits are the handoff.

You then rebase and fast-forward. Do not message a worker to "rebase and merge
your branch" — a drone 150k tokens deep costs a fortune per turn, and the work is
already committed and reachable by branch name. You have the cheap context for
merging; spend yours, not theirs. If a rebase conflicts, resolve it yourself
upstream of the merge.

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

**Put a hard stop in every prompt. This is the single highest-value line in a
worker's briefing** — three prior runs died with workers grinding silently on test
problems, and the run that carried this rule had all three workers escalate
correctly at a cost of one message each:

> If the same failure repeats twice, or you need a file you don't own, or the spec
> is ambiguous: `SendMessage` the orchestrator with the specific question and
> **stop**. Do not attempt a third fix.

Say explicitly that *you* are its advisor, that asking is cheaper for the team than
grinding, and that **a question is a success, not a failure**. A soft "ask if
unsure" does not work; workers read it as permission to keep trying. Also tell it
not to call `advisor` itself — you are the larger model and you hold the plan.

### 3a. There is NO shared task board for a worktree swarm — the prompt is the only briefing

**Verified empirically 2026-07-29 at the cost of one wasted dispatch round. Do
not re-derive this, and do not seed a board.**

`isolation: "worktree"` and the shared task board are **mutually exclusive**, so
for a swarm as this skill defines it the board is simply not available:

- The `Agent` tool spawns **subagents**, not teammates. `name` makes one
  addressable by `SendMessage`; it does **not** enrol it in an agent team.
- **Subagents have no `TaskCreate` / `TaskGet` / `TaskList` / `TaskUpdate`.**
  Those are teammate-only. A worker told to read its spec off the board finds the
  tools absent and stops, having paid its full startup cost for nothing.
- Teammates, conversely, **do not get worktree isolation**. You cannot have both.

So **everything a worker needs goes in its spawn prompt**: owned paths, settled
decisions, acceptance criteria. Budget for it — three fully-specified prompts is a
real slice of orchestrator context and it is not optional.

`SendMessage` **does** work both ways for background subagents (worker → `main`,
`main` → worker by name), despite docs implying teammates-only. That is the
escalation channel and it is what makes the hard-stop rule work. Same session,
verified.

If you ever run a genuine agent team (no worktrees): **`TaskCreate` is unsafe in
parallel** — two calls in one message both read the same stale max id, and the
second pair silently overwrites the first (six creates produced four tasks).
Serialize them. The board is also team-scoped, so plain subagents never see it.

<details>
<summary>Superseded teammate/board guidance (kept for the API shapes only)</summary>

A teammate is spawned via the `Agent` tool's `name` parameter and joins the
session's implicit **agent team** — which gives two things a bare background
subagent does not: a shared **task list** (`TaskCreate` / `TaskList` /
`TaskUpdate`) and a mailbox (`SendMessage`).

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

</details>

### 3a-next. Try this next run: teammates that make their OWN worktrees

The §3a dead end is only a dead end for **harness** isolation. The two features
conflict because `isolation: "worktree"` is a harness feature — but this project
already has its own, independent of it:

```bash
mise run worktree:new -- <issue|name>     # -> .worktrees/<slug>/, own branch
```

`warp` drives its whole single-issue cycle on that task. A **teammate** can run it
too. So the shape worth trying is:

1. Spawn workers as teammates — `name`, **no `isolation` parameter**.
2. Each worker's first action is `mise run worktree:new -- <its-unit>`, then it
   works there via absolute paths for the rest of its run.
3. It reads its spec off the shared task board and flips its own status.

If that holds, it is strictly better than what this run did: the task board and
mailbox come back, the orchestrator stops spending context on three
fully-specified prompts, **and** the harness worktree-reclamation trap disappears
entirely — a `mise` worktree is not auto-removed when its agent exits, so
resuming a stopped worker cannot land it in a sibling's checkout.

**Verified 2026-07-30** (haiku teammate, `name` + no `isolation`, probed directly):

- **Teammates DO get the `Agent` tool, and nesting actually works.** Full tool set
  observed: `Agent, Artifact, Bash, Edit, Read, Skill, ToolSearch, Write, advisor,
  Cron*, EnterWorktree, ExitWorktree, Monitor, NotebookEdit, SendMessage, Task*,
  WebFetch, WebSearch`. It called `Agent`/`Explore` and got the right answer back.
  So the "delegate broad searches downward" advice below is live, not aspirational.
  Tool access is decided by the **agent definition's `tools` field**, not by
  teammate-ness — `Explore`/`Plan` are the capped ones (`Agent` explicitly removed),
  `general-purpose`/`claude` are `*`. Don't go past worker → Explore; that grandchild
  is a leaf by definition and deeper nesting buys nothing.
- **A named teammate does NOT run the `Agent` call's `prompt`.** Spawning with `name`
  returns "will receive instructions via mailbox" and the agent sits **idle** — it
  posted an `idle_notification` without touching the brief. The work only started
  after an explicit `SendMessage`. `run_in_background: false` is also ignored: named
  teammates are always async. **So dispatch is two steps** — spawn with a minimal
  prompt, then `SendMessage` the actual brief. Budget for that; a swarm that assumes
  the spawn prompt ran will stall silently with N idle workers.
- **Each idle transition costs the orchestrator a turn.** A teammate emits an
  `idle_notification` when it has nothing to do — including right after delivering a
  report, so you get woken twice per unit. Harmless with 3 workers, but it is a real
  per-worker tax on the orchestrator's context, and it argues for the same batching
  rule as everything else: fewer, fatter workers.
- **Confirmed: teammates start in the main checkout's cwd** (`/home/bramh/skill-tree-of-life`),
  so there is a window before step 2 completes where a careless edit lands on shared
  state. Since the brief now arrives by `SendMessage` anyway, make "create your
  worktree first, then absolute paths only" the first line of *that* message, and keep
  the explicit-path `git add` rule regardless.
- `EnterWorktree` may refuse a `.worktrees/` path (its contract names
  `.claude/worktrees/` for switching). Working via absolute paths without entering
  is proven — a worker did exactly that successfully this run — so don't block on
  `EnterWorktree` if it refuses.
- Teams still needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` **at launch**, and
  `TaskCreate` must still be serialized, not called in parallel.

### 3b. Token economy — the binding constraint, and how to actually respect it

A swarm is throttled by the **5-hour rate-limit window**, not by anything you can
read from inside the session. You cannot query your own remaining budget, so a
"stop at 95%" guard is not implementable. Bound the *work* instead.

**Measured, one run, three workers each doing two units:**

| Worker | Tokens | Tool calls | Notes |
|---|---|---|---|
| cheapest | 147k | 64 | clean run, no escalation |
| middle | ~197k | 65 | one escalation + one forced worktree move |
| dearest | 199k | 93 | ran the full suite repeatedly + `xvfb` shader boots |

The spread tracks **tool calls, not units of work.** The dearest worker did the
same amount of code as the cheapest and cost 35% more, entirely in verification
it was never asked for. That is the lever.

**Bound verification explicitly in every prompt.** Left open, a worker will build
a test harness for a panel whose acceptance is "it looks right", then re-run the
whole suite after each tweak:

- Name the fast loop (`mise run check`) and say it is the loop.
- Cap the full suite: run it **once** before reporting, not per edit.
- **Forbid authoring new test suites** unless you name one. Visual acceptance does
  not get a GUT harness.
- Forbid `xvfb`/real-backend boots unless the unit touches a `.gdshader`.

**Batch units per worker — validated, keep doing it.** Two units in one hot
worktree cost 147k total, against the 150–200k a *single*-unit worker cost in
earlier runs. Startup and codebase orientation is the fixed cost; the second unit
rides nearly free. Batch by **shared context** (both units read the same
subsystem), not by issue size. 2–3 workers × 2 units beats 6 × 1 outright.

**Have workers delegate broad searches downward.** A worker with the full tool set
can spawn its own `Explore` subagent, which reads excerpts rather than whole files
and returns only the conclusion. Worth instructing when a unit needs "where is X
handled across the repo" — the orientation cost lands in a cheap throwaway context
instead of the worker's. **Nesting is confirmed permitted** (see §3a-next) for both
harness-isolated workers and teammates; what remains unmeasured is what it saves.

**Plan for running out.** Assume the window may close mid-swarm, and make that
survivable rather than catastrophic:

- Workers commit **after each unit**, never only at the end. A killed worker then
  loses one unit, not two.
- Merge each branch as it lands. Do not batch merges to the end — four merged
  units beat six unmerged ones.
- When a worker dies mid-unit, **commit its uncommitted worktree state yourself**
  as an explicit `wip(...)` commit that says what is unfinished, and write the
  blocker onto the issue. Never leave work as loose worktree state, and never
  leave the issue `in-progress` with nobody on it.

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

**Do not accept a worker's claim that a failure is pre-existing.** Two workers in
one run reported "975/976, the failure is a pre-existing baseline flake, confirmed
by stashing my changes." Both were wrong: their baseline included a *sibling
worker's* commit that had landed in the shared worktree. `master` was green at
976/976 the whole time. Check the baseline yourself with a real `master` run — it
is one command, and it is the difference between merging a genuine regression and
not.

The regression in that case was in the orchestrator's own pre-dispatch seam, and
only became reachable once a worker implemented the first real override of it.
**Expect your seam's bugs to surface at merge, not when you wrote it.**

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

### A worker's green run does not transfer — refresh the class cache after you land

If a worker introduced a new `class_name`, it ran
`godot --headless --editor --quit` **in its own worktree** and went green there.
The main checkout has its own `.godot/`, so right after your cherry-pick master
fails with `Could not find type "X" in the current scope` — plus a cascade of
"Parse error" / "Cannot infer the type of …" from every file that touches it.
Nothing is wrong with the diff; the cache is stale. Refresh it on master, then
re-run.

That refresh is also what generates the `.uid` for a worker's new test file, so
until you run it **GUT silently does not collect the new test** — the suite looks
green at the *old* script count. Compare `Scripts` / `Tests` totals before and
after; if the totals didn't move, the new test never ran.

Per `.claude/rules/godot-workflow.md`, an editor pass can silently round-trip any
scene it touches — and master is a shared checkout that usually carries the
user's uncommitted WIP. `md5sum` the modified files before and after, and restore
from a copy if anything moved.

- **Worker worktrees live under `.claude/worktrees/agent-<id>/`, on branch
  `worktree-agent-<id>`** — not under `.worktrees/`, and not from
  `mise run worktree:new`. The harness creates them, branched from `master`'s tip
  at spawn time, and returns the path and branch in the tool result. That's the
  substrate; `mise`'s worktree tasks are for `warp`'s single-checkout cycle.
- **Resuming a worker that stopped clean can drop it into ANOTHER worker's
  worktree.** The harness reclaims an `isolation: "worktree"` worktree when its
  agent exits without changes. `SendMessage` then resumes that agent from its
  transcript — but with no worktree of its own, and it can land in a *sibling
  worker's* checkout. Observed: a worker stopped to ask a question, was resumed
  with the answer, and committed onto another live worker's branch while that
  worker's uncommitted WIP sat in the same tree. Nothing errored.

  The blast radius is real: one `git add -A` there would have committed half of
  another agent's unfinished work.

  **Before resuming any worker that reported and stopped, create it a fresh
  worktree** (`git worktree add .claude/worktrees/agent-<name>-2 -b <branch> master`)
  and name the absolute path in your message. Tell every worker to `git add`
  **by explicit path, never `-A` or `-a`** — that is the standing mitigation, since
  you will not always notice the swap. If a stray commit does land on the wrong
  branch, leave it: if it is file-disjoint it merges fine from there, and telling a
  deep-context worker to disentangle git history is the most expensive possible fix.
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
