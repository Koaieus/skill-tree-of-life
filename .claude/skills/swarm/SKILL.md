---
name: swarm
description: Direct a team of parallel subagents through pre-planned, parallelizable work — one big issue split into units, or several small issues at once. Read the issues ONCE, delegate exploration downward to drone/Explore(haiku) subagents, cluster the work by shared context into a DAG, dispatch each unit as a backgrounded drone, and act on each completion immediately — merge, fix-then-merge, resume, or abandon-to-in-review. Use when the user says "swarm #<n>" / "swarm #<n>, #<m>", or asks to parallelize bulk/mechanical work across subagents. Only invoke as Opus, or as Sonnet when the plan is already written down.
---

# Swarm

One strong orchestrator, many fast workers. You are the **source of wisdom**,
the **DAG holder**, and the **reviewer-merger**. The workers do the typing —
each in its own worktree, each in its own context window — and talk back to you
when they hit something they can't resolve alone.

## Why this skill exists — token economy through delegation

The binding constraint is **your context window, not wall-clock.** A 10-issue
swarm with the orchestrator at 30–50k at launch is vastly cheaper than the
same swarm launched at 70–80k, because the 10+ downstream turns the swarm
needs after the last drone finishes (review, rebase, merge, start-next,
respond to questions) each spend ~15–20k on a context that has *kept growing*
throughout the run. **Low at launch = late blow-up = the room you need to land
the last issue cleanly.** Once you're at 150–200k, every merge turn compounds,
and the last 5% of the swarm costs more than the first 50%.

Two levers, in order of impact:

1. **Delegate exploration downward.** You read the issues ONCE. Then any
   exploration that follows — verifying the issue's claims, finding what's
   already landed, grepping the consumer of a unit's output, checking the
   baseline-test count — runs in throwaway `drone` / `Explore(model=haiku)`
   subagents that return only the conclusion. The reading and grepping never
   tax your window; you build the plan on the payloads they hand back.
2. **Group by shared context, not by file ownership.** Three issues reading
   the same subsystem, the same rules, the same docs are **one worker doing
   three units with hot context** — the second rides nearly free and can fix
   bugs in the first while its context is still loaded. Three workers on the
   same subsystem pay the orientation cost three times. The cluster map and
   the DAG of dependencies are yours to hold, before anything dispatches.

That is the swarm in two sentences: **read once, delegate the rest
downward**, and **keep the orchestrator's context small enough that the late
merge turns stay cheap.** Everything below is mechanics in service of that.

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
   (see §2). What fails this gate is work that won't come apart at all.
3. **Mechanical enough for a smaller model**, given red-green instructions: a
   failing test (or an exact spec) defines done.
4. **No human input mid-flight.** If the user must weigh in halfway, the swarm
   stalls with N worktrees open.

5. **You have the budget for it.** A swarm is the most token-expensive thing in
   this repo, and the 5-hour window is the binding constraint — see "Size the
   swarm to the window" below. Six workers dispatched at 81% ran the window to
   93% *while being told to stop*.

Being Opus is itself part of the gate. Sonnet may drive a swarm only when the
decomposition is already written down — not when it must be derived.

## Size the swarm to the window — do this BEFORE decomposing

Measured 2026-08-03: **one issue costs roughly 10–20% of a fresh 5-hour window**,
depending on size and on how many iterations the drone needs. Stopping a running
worker is **not free** — it costs a turn per worker, and shedding six mid-flight
workers cost ~10% on its own. So the arithmetic has to happen before dispatch,
not after:

> **units × 15% + (workers × 2% shutdown reserve) must fit in what's left.**

**Second measurement, 2026-08-03 — a run that SUCCEEDED** (the numbers above came
from one that didn't). 3 workers, 4 units, one of them a warm worktree resume, two
escalations each resolved in a single message: **~48% of a fresh window** at the
point 3 units were merged and the 4th implemented, with review/merge/teardown and
the knowledge sweep pushing it somewhat past that. Call it **~12% per unit
including all orchestration** — skill load, 4 issue reads with comments, pre-flight
audits, 3 diff reviews, 3 rebase+merges, 4 full-suite runs and board upkeep.

The formula predicted 66% for that shape, so it over-estimates by roughly 1.4×.
**Keep the 15% anyway.** It is a deliberate ceiling covering the case a worker
grinds instead of asking, and the cheap run only happened because every brief
capped verification (§4b) and because the orchestrator ran the cross-file audits
in its own context rather than paying a drone to search. Lower the constant and
you lose the margin exactly when a run goes badly — which is when it matters.

You cannot query your remaining budget, so **ask the user for the number** if you
don't already have it — one question is cheaper than a forced break-off. Then:

| Window remaining | What that buys |
|---|---|
| < 40% | Don't swarm. Run `warp` on the single highest-value issue. |
| 40–60% | 2 workers, 1 unit each. |
| 60–80% | 3 workers, ~2 units each. |
| > 80% | 4–5 workers. Beyond that you are betting the window. |

**Ten workers is never the answer**, however tempting the backlog looks. A swarm
that hits 100% mid-flight loses every uncommitted unit *and* the turns needed to
shut down cleanly — strictly worse than a smaller swarm that finishes.

**Prefer landing 4 issues to starting 12.** The user's goal is issues closed, and
an unmerged worktree closes nothing. When in doubt, cut the worker count, not the
per-worker verification — verification is what makes a unit mergeable.

## The cycle

### 1. Read the issues ONCE, then delegate exploration downward

```bash
gh issue view <n> --comments        # once per issue, body + every comment
```

Read each issue **once**, with comments, full. Do not re-read. Do not page
through other issues "for context". Do not run a third `gh` call to "double
check" a number — you will burn `gql` quota before you start, and you gain
nothing the first read didn't give you. If the previous agent in this seat
exhausted itself mulling over the same issue four times, do not repeat that
failure mode: read once, decide, move to §1a.

**Never spawn anything exploratory in your own context.** The list of things
the issue may have wrong, glossed over, or already-landed-partially — verify
those by *delegation*, not by reading more yourself. Drop one of these and
let it absorb the context:

- **`drone`** (OpenAI harness) or **`Explore` with `model: "haiku"`** (Claude
  harness) for: "is the seam the issue names actually present in master?",
  "has any of this already landed?", "where does X get called from?", "what
  tests already exist for this subsystem?", "is the reported baseline flake
  real?". They read excerpts and return only the answer.
- Run several **in parallel** — one per question, one per probe — they share
  no context with you and absorb nothing of yours. They are the brunt of the
  pre-flight context burn.

When they come back, you have the verified picture — claims checked, what's
already shipped mapped, baseline tests named. That is your substrate for §2.
You spent one issue-read's worth of tokens to get it, not five.

### 1a. The acceptance-parameters preview — and why you delegate this too

Issues filed by agents (or rushed through design) sometimes sneak in a
cop-out: a feature quietly descoped to hit "done", a thing removed because it
was hard, an acceptance that says "write the test" while the spec said
"wire it into the HUD". You, as orchestrator, should see those before you
commit workers to the spec — but reading every acceptance line across 10
issues back into your own window is a big early token spend, and it
**compounds** through every downstream turn.

So delegate the precedent to a subagent too:

> Have one `Explore`/`drone` tabulate, per issue: (a) the literal acceptance
> bullet(s), (b) any sibling-issue linkage the body claims, (c) anything
> descopable that smells like an agent picked the easy way out. One row per
> issue. Return the table only.

You read the table — 1–2k tokens for a 10-issue swarm, not 15k of reading
every body twice — and *that* is your one approval pass before dispatch. If
the subagent flagged a cop-out, push back to the user then; never silently
inherit a descoped spec into a worker's brief.

If the swarm is small (≤3 issues) you can do this pass inline and skip the
subagent — the delegation gate is for the bulk case where the table is the
win.

### 2. Build the shared-context DAG, then decompose into units

Two workers must never touch the same file *at the same time*. But that rule
is downstream of the actual decomposition step, which is **cluster by shared
context first, partition by file second**.

The fixed cost a worker pays before it writes a line — brief, issue recall,
orienting in the subsystem, finding the seam — is the dominant token cost of
a unit. Two issues that touch the same files split across two workers pay
that cost **twice, for the same reading**. Give both to one worker and you
pay it once: the second unit rides nearly free, *and* the worker can fix
bugs in the first unit's code while its context is still hot, *and* anything
the worker creates in unit 1 that unit 2 needs is already in its window.

**The decomposition order:**

1. **Cluster the issues by subsystem** — which ones read the same files, the
   same rules, the same docs? That clustering **is** your worker list. One
   worker per cluster.
2. **Only then** check file-disjointness *between* clusters, and sequence any
   cluster pair that overlaps into waves: wave 1 goes out in parallel, you
   review and merge it, then wave 2 dispatches from the new `master` tip.

Note this inverts the naive read of "two workers must never touch the same
file": that rule pushes you toward *more* workers, and shared-context batching
pushes toward fewer. **Fewer wins.** File overlap inside one worker is not a
conflict at all — it's just sequential edits in one worktree, the cheapest
thing here. Overlap only costs you *across* workers.

2–3 workers × 2–3 units beats 6 × 1 outright, on tokens and on turns (each
worker also costs you two idle-notification wakeups). If you find yourself with
six workers, look for the two clusters you failed to merge.

**Within a wave, the file boundary is absolute.** Write each worker's file
list into its prompt as an ownership boundary: *"you own exactly these paths;
if the task seems to need a file you don't own, stop and report it."*

**Shared-file work (one `.tres` every unit must touch, a registry every unit
appends to) is yours.** Do it in the main checkout before you dispatch, or as
an integration commit after you merge. Never hand it to two workers in one
wave.

**Find the shared contract before you dispatch, and commit it first.** N
units implementing "the same kind of thing" almost always need one seam none
of them owns — a base-class method they all override, a registration call, a
way to say "I have nothing to show". Left undiscovered, each worker invents
its own and none of them merge cleanly. Grep (via the §1 exploration
subagents, not in your own context) for the *consumer* of the units' output
and see what it actually calls; that is where the seam hides. Write it, test
it, commit it to `master`, and only then spawn — workers branch from the tip,
so a seam committed after dispatch is invisible to them.

**Pre-flight the units' envelopes against real content.** A stub sized for
placeholder text is not evidence the real thing fits. One unit in this run
was blocked at the finish line because its panel's authored size had only
ever held five dummy labels, and growing it collided with positions authored
in files no content unit was allowed to touch. That was foreseeable in one
minute of looking before dispatch, and cost a full escalation round
afterwards. When units fill a layout you own, check the worst-case content
fits *first* (delegate the actual measurement to a subagent — see §1).

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

### 3. Dispatch — one swarm, one message, every worker backgrounded

**Claim every issue on the kanban before you spawn anything:**

```bash
mise gh-project -- status <n> in-progress    # once per issue, at dispatch
```

This is the *persistent* board (`mise gh-project`), not the in-session task list
of §3a — they are different surfaces and only this one survives the session. An
unclaimed issue looks free, so a later swarm (or the user) picks it up and
duplicates the work. Flip it back to `ready` if you dispatch nothing.

**Dispatch is TWO steps, and skipping the second stalls the whole swarm.** A
named teammate does *not* run the `Agent` call's `prompt` — it returns "will
receive instructions via mailbox" and sits idle (verified 2026-07-30). So:

**Step 1 — spawn every worker in a single message** (that is what makes them run
in parallel). Per `Agent` call:

- **`name`, and NO `isolation` parameter.** Workers are teammates; each makes
  its own worktree via `mise run worktree:new` (§3a). Harness isolation would
  take the shared task board away.
- `model: "sonnet"`, or `"haiku"` for ultra-mechanical work (rename, mass
  string-replace, boilerplate).
- `run_in_background: true` (ignored for named teammates — they're always async).
- A **minimal** prompt. The real brief comes in step 2; anything here is not read.

**Step 2 — `SendMessage` each worker its brief.** The first line must be:

> Run `mise run worktree:new -- <your-unit>` as your FIRST action, then use
> absolute paths into `.worktrees/<slug>/` for everything after. Do not edit
> anything before that worktree exists.

That line is the isolation guarantee. Teammates start in the **main checkout's
cwd**, so until the worktree exists a careless edit lands on shared state.

Then: **"Invoke the `drone` skill, then do the following."**
  `drone` carries the flow rules so you don't restate them N times. (Subagents do
  inherit the skill list — verified. If one ever reports it can't find `drone`,
  tell it to `Read .claude/skills/drone/SKILL.md` instead; it's plain markdown.)

Each worker reports its own `BRANCH:` (the `<slug>` from `worktree:new`). Record
them — they are your merge handles, and the only way back to a worker's commits.
Note each idle transition costs you a turn: a teammate emits an
`idle_notification` when it has nothing to do, including right after reporting,
so you get woken twice per unit. Another argument for fewer, fatter workers.

Give each worker its acceptance test up front. A worker that can run
`mise run test:one -- res://test/unit/test_foo.gd` and see green knows it is
done; one that can't will report "looks right" and be wrong.

**Put a hard stop in every prompt. This is the single highest-value line in a
worker's briefing** — three prior runs died with workers grinding silently on
test problems, and the run that carried this rule had all three workers
escalate correctly at a cost of one message each:

> If the same failure repeats twice, or you need a file you don't own, or the spec
> is ambiguous: `SendMessage` the orchestrator with the specific question and
> **stop**. Do not attempt a third fix.

Say explicitly that *you* are its advisor, that asking is cheaper for the team
than grinding, and that **a question is a success, not a failure**. A soft "ask
if unsure" does not work; workers read it as permission to keep trying. Also tell
it not to call `advisor` itself — you are the larger model and you hold the plan.

### 3a. Workers make their OWN worktrees — that is how you get the task board too

**Verified 2026-07-30. This supersedes the 2026-07-29 finding that the board and
worktrees were mutually exclusive — they were, for *harness* isolation only.**

`isolation: "worktree"` and the shared task board really are exclusive: subagents
have no `TaskCreate` / `TaskGet` / `TaskList` / `TaskUpdate` (teammate-only), and
a worker told to read its spec off a board it can't see stops, having paid full
startup for nothing. But this project has its own worktrees, independent of the
harness:

```bash
mise run worktree:new -- <issue|name>     # -> .worktrees/<slug>/, own branch
```

`warp` drives its entire single-issue cycle on that task, and a teammate can run
it too. So workers spawn as **teammates** (`name`, no `isolation`) and make their
own worktree as their first action. You get all three: real isolation, the shared
task board, and the mailbox.

It's strictly better than harness isolation on three counts — the board and
mailbox come back, the orchestrator stops spending context on N fully-specified
prompts, and the worktree-reclamation trap disappears (a `mise` worktree is never
auto-removed, so resuming a stopped worker cannot land it in a sibling's
checkout).

**The tradeoff, stated plainly:** harness isolation was a hard guarantee; this is
a convention. The worker is in the shared main checkout until step 2 of its own
brief completes. The mitigations are the worktree-first line in the `SendMessage`
brief and `drone`'s explicit-path `git add` rule — both mandatory, neither
optional.

**The task board is shared by *teammate-ness*, not by the filesystem.** Worktrees
are separate checkouts and share no working-tree files — so don't put the task
list in a repo file and expect workers to see each other's updates. It's the
harness's team-scoped in-session board or nothing.

**`TaskCreate` is still unsafe in parallel** — two calls in one message both read
the same stale max id and the second pair silently overwrites the first (six
creates produced four tasks). Serialize them.

**`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is already set in this user's
`~/.claude/settings.json`. Do not spend a turn echoing it.** It is read at launch
and cannot be enabled mid-session, so the only case worth handling is the one
where a spawn *actually* comes back without teammate behaviour — deal with it
then, reactively. A pre-flight check that has passed every time is a turn you
are paying for nothing, and turns are the scarce resource here.

`SendMessage` **does** work both ways for background subagents (worker → `main`,
`main` → worker by name), despite docs implying teammates-only. That is the
escalation channel and it is what makes the hard-stop rule work. Same session,
verified.

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
mid-session; it's a relaunch. If it's off and the user wants teammates, say so
and let them relaunch — don't seed a board that the workers will never see (see
the gotcha below).

**Launch-timing trap:** the `echo` reads your Bash shell, not the running
Claude process. If the user adds the flag mid-session, a fresh Bash shows `1`
while the session that decided team-membership at *its* startup still has
teams off. So a value that flipped `unset → 1` partway through the session is
**not** proof teams is live — confirm with a relaunch before seeding a board
you're betting the swarm on.

Flow when teams is on:

1. **Seed the board before dispatch.** One `TaskCreate` per unit; put the
   ownership boundary (the exact paths it owns) and the acceptance test right
   in the `description`. Any shared-file integration step you own becomes its
   own task, with `addBlockedBy` naming the unit tasks that must land first —
   the dependency is now explicit on the board instead of living only in your
   head.
2. **Spawn with `name`.** Still `isolation: "worktree"`, `model: "sonnet"` (or
   `"haiku"`), `run_in_background: true`. Give each teammate a stable `name`
   (`field-noise`, `field-gaussian`) and tell it in its prompt **which task id
   it owns** and to `TaskUpdate` it: `in_progress` on start, `completed` only
   on green. `drone` still governs its flow.
3. **Watch, don't poll narratively.** `TaskList` shows the live board. A
   teammate stuck on a blocker is unblocked by `SendMessage` to its name —
   worktree and context intact, far cheaper than a cold respawn (same as the
   Collect rule).

Gotchas:

- **The board is team-scoped.** Tasks are shared only among teammates on the
  same team. Seed a board, then spawn plain (nameless / teams-off) subagents,
  and they won't see it — you've built a plan nobody reads. Board and
  teammates go together or not at all.
- **A teammate still cannot see this conversation.** The task `description`
  is its briefing — everything the fire-and-forget prompt would carry (owned
  files, acceptance test, "done" definition) goes there or in the spawn
  prompt, not left implicit because "it's on the board."
- Teardown, review, and merge (steps 5–7) are unchanged — a teammate's
  worktree and branch behave exactly like a background worker's.

</details>

### 3a-i. Field notes on the teammate path (verified 2026-07-30)

Details behind §3a, from a haiku teammate probed directly:

- **Teammates DO get the `Agent` tool, and nesting actually works.** Full
  tool set observed: `Agent, Artifact, Bash, Edit, Read, Skill, ToolSearch,
  Write, advisor, Cron*, EnterWorktree, ExitWorktree, Monitor, NotebookEdit,
  SendMessage, Task*, WebFetch, WebSearch`. It called `Agent`/`Explore` and got
  the right answer back. So the "delegate broad searches downward" advice
  below is live, not aspirational. Tool access is decided by the **agent
  definition's `tools` field**, not by teammate-ness — `Explore`/`Plan` are
  the capped ones (`Agent` explicitly removed), `general-purpose`/`claude`
  are `*`. Don't go past worker → Explore; that grandchild is a leaf by
  definition and deeper nesting buys nothing.
- **A named teammate does NOT run the `Agent` call's `prompt`.** Spawning with
  `name` returns "will receive instructions via mailbox" and the agent sits
  **idle** — it posted an `idle_notification` without touching the brief. The
  work only started after an explicit `SendMessage`. `run_in_background: false`
  is also ignored: named teammates are always async. **So dispatch is two
  steps** — spawn with a minimal prompt, then `SendMessage` the actual brief.
  Budget for that; a swarm that assumes the spawn prompt ran will stall
  silently with N idle workers.
- **Each idle transition costs the orchestrator a turn.** A teammate emits an
  `idle_notification` when it has nothing to do — including right after
  delivering a report, so you get woken twice per unit. Harmless with 3
  workers, but it is a real per-worker tax on the orchestrator's context, and
  it argues for the same batching rule as everything else: fewer, fatter
  workers.
- **Confirmed: teammates start in the main checkout's cwd**
  (`/home/bramh/skill-tree-of-life`), so there is a window before step 2
  completes where a careless edit lands on shared state. Since the brief now
  arrives by `SendMessage` anyway, make "create your worktree first, then
  absolute paths only" the first line of *that* message, and keep the
  explicit-path `git add` rule regardless.
- `EnterWorktree` may refuse a `.worktrees/` path (its contract names
  `.claude/worktrees/` for switching). Working via absolute paths without
  entering is proven — a worker did exactly that successfully this run — so
  don't block on `EnterWorktree` if it refuses.
- Teams still needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` **at launch**,
  and `TaskCreate` must still be serialized, not called in parallel.

### 3b. Token economy — the binding constraint, and how to actually respect it

A swarm is throttled by the **5-hour rate-limit window**, not by anything you
can read from inside the session. You cannot query your own remaining budget,
so a "stop at 95%" guard is not implementable. Bound the *work* instead.

**Measured, one run, three workers each doing two units:**

| Worker | Tokens | Tool calls | Notes |
|---|---|---|---|
| cheapest | 147k | 64 | clean run, no escalation |
| middle | ~197k | 65 | one escalation + one forced worktree move |
| dearest | 199k | 93 | ran the full suite repeatedly + `xvfb` shader boots |

The spread tracks **tool calls, not units of work.** The dearest worker did
the same amount of code as the cheapest and cost 35% more, entirely in
verification it was never asked for. That is the lever.

**Bound verification explicitly in every prompt.** Left open, a worker will
build a test harness for a panel whose acceptance is "it looks right", then
re-run the whole suite after each tweak:

- Name the fast loop (`mise run check`) and say it is the loop.
- Cap the full suite: run it **once** before reporting, not per edit.
- **Forbid authoring new test suites** unless you name one. Visual acceptance
  does not get a GUT harness.
- Forbid `xvfb`/real-backend boots unless the unit touches a `.gdshader`.

**Have workers delegate broad searches downward too, not just you.** A worker
with the full tool set can spawn its own `Explore` subagent, which reads
excerpts rather than whole files and returns only the conclusion. Worth
instructing when a unit needs "where is X handled across the repo" — the
orientation cost lands in a cheap throwaway context instead of the worker's.
**Nesting is confirmed permitted** (see §3a-i) for both harness-isolated
workers and teammates.

**Plan for running out.** Assume the window may close mid-swarm, and make that
survivable rather than catastrophic:

- Workers commit **after each unit**, never only at the end. A killed worker
  then loses one unit, not two.
- Merge each branch as it lands. Do not batch merges to the end — four
  merged units beat six unmerged ones.
- When a worker dies mid-unit, **commit its uncommitted worktree state
  yourself** as an explicit `wip(...)` commit that says what is unfinished,
  and write the blocker onto the issue. Never leave work as loose worktree
  state, and never leave the issue `in-progress` with nobody on it.

### 4. Collect — act on each completion immediately, do not batch

`drone` mandates a terse structured report. Read those, not the diffs. If a
worker's report is a wall of text, that's a `drone` violation — don't
propagate it into your summary to the user.

**Backgrounded workers report as they finish. Do not wait for the whole
swarm — act on each report the moment it lands.** The cycle below is per
unit; running it serially per completion is what keeps `master` moving and
your context bounded (you review the diff while the other workers keep
typing — that diff is harvested at peak freshness and never re-read).

For each worker report, run this decision tree:

```bash
git -C .worktrees/<slug> log master..HEAD --stat   # scope first
git diff master...<branch> --stat                  # what files it touched
git diff master...<branch>                         # then content
```

1. **Ownership check.** Did it touch only its owned paths? If it strayed into
   a file outside its boundary, that's a bug to understand *before* you read
   the content — either the worker guessed wrong (resume-and-redirect) or your
   boundary was wrong (fix the boundary, restate the unit, merge is fine).
2. **Content check.** Reads as the spec asked? No quiet cop-outs (a feature
   silently descoped, a thing removed "because the test was hard", a TODO
   left where the issue asked for code)? Compare against the
   acceptance-parameters table from §1a — if the worker added an escape that
   the issue spec rejected, push back.
3. **Test check.** Run `mise run test` from the merged tip after the
   fast-forward, not the worker's claim. A green worker is not a green
   `master`.

Then **branch on quality**, in decreasing order of frequency:

- **Perfect — merge to `master` now.** Rebase onto current `master`, fast-forward,
  amend `Closes #<n>` (§6), push or queue, run `mise run test`, move the issue
  to `in-review` on the kanban. Do not let it sit.
- **Almost perfect — fix it yourself, then merge.** The diff is 95% right and
  the gap is a one-line thing the worker would burn a full escalation round to
  arrive at. You are the smart model and the cheap context — make the edit in
  your window, then merge. Spending a worker turn on a `SendMessage`-then-
  re-review is *more* tokens than the fix itself.
- **Badly done but recoverable — resume the drone.** `SendMessage` the same
  agent id with a sharp diagnosis and the specific re-direction. Its worktree
  and its context are still alive; continuing it is far cheaper than a cold
  respawn and it keeps the unit's accumulated reading hot. State clearly what
  was wrong and what the new target is — the orchestrator is the source of
  wisdom here, not a passive reviewer.
- **Genuinely stuck — stop, do not grind.** A worker that reports the same
  blocker twice after a resume, or surfaces something that is plainly a real
  design fork the user must settle, is not solvable by more drone turns. Move
  the issue to `in-review` on the kanban with a one-line comment naming the
  fork, and **focus on the remainder of the swarm.** Do not let one unsolvable
  unit stall the merge queue for the other six.

A worker that reported a blocker (needed a file it didn't own; test won't go
green; ambiguity in the spec) on its *first* report has done the right thing
under the hard-stop rule — escalate it to "almost perfect" / "badly done"
paths above. The blocker itself is signal, not a failure of the worker.

### 5. Review

You are the reviewer. The workers are smaller models and had no advisor.

```bash
git diff master...<worktreeBranch> --stat     # shape first
git diff master...<worktreeBranch>            # then read it
```

Verify the ownership boundary actually held (`--stat` shows any file a worker
shouldn't have touched) before you look at content. Nothing merges unreviewed.

**Do not accept a worker's claim that a failure is pre-existing.** Two
workers in one run reported "975/976, the failure is a pre-existing baseline
flake, confirmed by stashing my changes." Both were wrong: their baseline
included a *sibling worker's* commit that had landed in the shared worktree.
`master` was green at 976/976 the whole time. Check the baseline yourself with
a real `master` run — it is one command, and it is the difference between
merging a genuine regression and not.

The regression in that case was in the orchestrator's own pre-dispatch seam,
and only became reachable once a worker implemented the first real override of
it. **Expect your seam's bugs to surface at merge, not when you wrote it.**

A green suite proves the worker's *mechanism*, not the *outcome*. That gap is
widest on visual work: a z-index assertion fully determines draw order, but no
assertion tells you a semitransparent band is legible on screen, and a shader
that compiles can still render nothing. When a unit changes what the game
looks like, either drive it (`mise run play`, `/verify`) or say plainly to
the user that you confirmed the plumbing and not the pixels. Don't let "tests
pass, shader compiles" quietly stand in for "it looks right."

### 6. Merge, one branch at a time

Per branch, in sequence, exactly as `warp` step 6 describes: rebase the branch
onto `master` from inside its worktree, then fast-forward `master`. Sequential
is not a limitation — each rebase re-tests the *next* branch against the
merged result of the previous ones, which is the only place a cross-unit break
surfaces.

Run `mise run test` after each merge, not only after the last. When something
breaks, you want to know which branch did it.

If the units were file-disjoint, every rebase is clean. A conflict here means
the decomposition leaked — fix the decomposition's consequence, not just the
conflict.

**Closing the issue(s).** Workers never write `Closes #<n>` themselves — you
add it, because only you know which branch is last. Amend it on before that
branch's rebase, while you're still upstream of the merge:

- **One issue, N units** — one `Closes #<n>`, on your integration commit, or
  amended onto the *final* branch's tip. Not on the others: whichever merged
  first would close the issue while the rest of the work is still in flight.
- **N independent issues** — one `Closes #<n>` per branch, each naming its
  own issue. Every branch is the last one for its issue.

`Closes` fires on **push**, not on the local fast-forward. So merging does
not close anything. Check `git status -sb` before you claim an issue is done,
and remember `master` may carry unrelated commits (yours, or another agent's)
that a push would ship alongside your work — surface that and let the user
decide.

Because the close is deferred to the push, move the issue on the kanban as
each one lands, so the board reflects reality even though the issue is still
open:

```bash
mise gh-project -- status <n> in-review     # branch landed on master, awaiting push
```

If a worker reported a blocker and stopped, put the issue back to `ready` (or
`backlog`) with a comment saying what blocked it — never leave it
`in-progress` with nobody on it. A stuck `in-progress` is the one state that
silently blocks the next swarm.

### 7. Teardown

**Teardown is now unconditional and yours.** The semantics inverted with §3a:
a harness worktree was auto-removed if untouched, but a `mise` worktree is
*never* auto-removed. That's the point — a stopped worker can be resumed into
its own checkout — but it means every worker leaves one behind, whether or
not it committed.

```bash
mise run worktree:ls                                # find the survivors
mise run worktree:rm -- <slug>                      # fuzzy-matches; per worker
git branch -d <slug>                                # -d, not -D: refuses if unmerged
```

Both plain forms work on a merged worker branch — reach for `--force` / `-D`
only once you know why the plain one refused. `remove` refuses while the
worktree is still `locked` (the agent hasn't exited) or dirty; `branch -d`
refuses when the branch isn't in `master`, which means you dropped a worker's
work. Neither is a formality to `--force` past.

## Gotchas

### A worker's green run does not transfer — refresh the class cache after you land

If a worker introduced a new `class_name`, it ran `mise run refresh` **in its
own worktree** and went green there.
The main checkout has its own `.godot/`, so right after your cherry-pick master
fails with `Could not find type "X" in the current scope` — plus a cascade of
"Parse error" / "Cannot infer the type of …" from every file that touches it.
Nothing is wrong with the diff; the cache is stale. Refresh it on master, then
re-run.

That refresh is also what generates the `.uid` for a worker's new test file, so
until you run it **GUT silently does not collect the new test** — the suite
looks green at the *old* script count. Compare `Scripts` / `Tests` totals
before and after; if the totals didn't move, the new test never ran.

Per `.claude/rules/godot-workflow.md`, an editor pass re-serializes scenes it
touches, and master is a shared checkout that may carry the user's
uncommitted WIP. `mise run refresh` is the whole check — it excludes
pre-existing dirt and hands back a verdict. Don't `md5sum` or stage copies.
Restore anything non-default it flags; ignore id and position noise.

- **Worker worktrees live under `.claude/worktrees/agent-<id>/`, on branch
  `worktree-agent-<id>`** — not under `.worktrees/`, and not from
  `mise run worktree:new`. The harness creates them, branched from `master`'s
  tip at spawn time, and returns the path and branch in the tool result.
  That's the substrate; `mise`'s worktree tasks are for `warp`'s single-
  checkout cycle.
- **Resuming a worker that stopped clean can drop it into ANOTHER worker's
  worktree.** The harness reclaims an `isolation: "worktree"` worktree when
  its agent exits without changes. `SendMessage` then resumes that agent
  from its transcript — but with no worktree of its own, and it can land in
  a *sibling worker's* checkout. Observed: a worker stopped to ask a
  question, was resumed with the answer, and committed onto another live
  worker's branch while that worker's uncommitted WIP sat in the same tree.
  Nothing errored.

  The blast radius is real: one `git add -A` there would have committed
  half of another agent's unfinished work.

  **Before resuming any worker that reported and stopped, create it a fresh
  worktree** (`git worktree add .claude/worktrees/agent-<name>-2 -b <branch>
  master`) and name the absolute path in your message. Tell every worker to
  `git add` **by explicit path, never `-A` or `-a`** — that is the standing
  mitigation, since you will not always notice the swap. If a stray commit
  does land on the wrong branch, leave it: if it is file-disjoint it merges
  fine from there, and telling a deep-context worker to disentangle git
  history is the most expensive possible fix.
- **Workers branch from `master` as it was when they spawned.** Merging
  branch A moves `master`; branch B is now behind. That's why step 6 rebases
  each branch immediately before its own merge, not all of them up front.
- **Don't let a worker call `advisor`.** You are the advisor — you're the
  larger model and you hold the plan. `drone` tells them this; don't undercut
  it by suggesting it in a worker prompt.
- **A worker's context is not yours.** It cannot see this conversation, the
  issue, or the sibling workers' units. Everything it needs goes in its
  prompt: the files it owns, the acceptance test, and what "done" means.
- **Relay, don't paste.** The whole point is your context stays small.
  Summarize worker reports for the user in your own words; a swarm whose
  orchestrator pastes N diffs has spent its context anyway and saved
  nothing.
- **Always `git -C <path>`, never bare `git` after a `cd`.** Bash's working
  directory persists across tool calls. `cd` into a worktree to run its
  tests and every later `git` command silently targets *that* worktree — a
  `merge --ff-only` aimed at master will cheerfully report "Already up to
  date" while merging a branch into itself. Nothing errors. Spell out the
  repo path on every git call.
- **A worker's fresh worktree cold-imports and dirties tracked `.import`
  files**, which makes `git rebase` refuse with "cannot rebase: You have
  unstaged changes." Run `git -C <worktree> checkout -- .` first. Same for
  the main checkout after a real-backend (`opengl3`) shader check — it
  re-imports every texture.
- **`master` can move under you mid-swarm.** Another agent may land commits
  in the shared main checkout while your workers run. That's fine — it's
  why step 6 rebases each branch immediately before its own merge — but
  *re-read `master`* before concluding a merge misbehaved.
- **Untracked files in the main checkout are invisible to worktrees**, so a
  test count taken there won't match a worker's. Compare tracked-only
  totals, and when a count is off, `git ls-files --error-unmatch <path>`
  before suspecting a worker. A file present in the main checkout's suite
  but absent from every worktree's is almost certainly untracked, not
  deleted by a worker.