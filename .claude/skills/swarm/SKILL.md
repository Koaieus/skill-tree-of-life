---
name: swarm
description: Direct a team of parallel subagents through pre-planned, parallelizable work — one big issue split into units, or several small issues at once. Read the issues ONCE, delegate exploration downward to `drone` (opencode) or `Explore(model=haiku)` (Claude Code) subagents, cluster the work by shared context into a DAG, dispatch each unit as a backgrounded worker, and act on each completion immediately — merge, fix-then-merge, resume, or abandon-to-in-review. Use when the user says "swarm #<n>" / "swarm #<n>, #<m>", "relay these" (a relay is a swarm with one drone in flight), or asks to parallelize bulk/mechanical work across subagents. Invoke as the strongest available model, or as Sonnet with an Opus `planner` subagent doing the DAG/fences/tiers (the planner fork, #857), or as Sonnet when the plan is already written down.
---

# Swarm

One strong planner, many fast workers, one Sage. You are the **DAG holder**
and the **train gate**; in a Sage run (`.claude/agents/sage.md`) the review
and the landing of each unit are Sage's, and your per-unit cost is one wake.
The workers do the typing — each in its own worktree, each in its own context
window — and ask Sage, not you, when they hit something they can't resolve
alone.

**Wake arithmetic (#857).** A subagent's *stop* always wakes its spawner,
whatever it wrote, so count wakes per unit, not messages. With Sage landing:
the drone stops once to yield to Sage (your wake), Sage reviews, approves and
runs `mise run land` in the same turn, nothing reaches you — **N+1 wakes for
N clean units**, the +1 being Sage's single `LANDED:` message. A failed land
costs one drone resume and no extra wake of yours. Without Sage, you are the
reviewer and lander and pay 2–3 wakes per unit.

## Why this skill exists — token economy through delegation

The binding constraint is **your context window, not wall-clock.** A 10-issue
swarm with the orchestrator at 30–50k at launch is vastly cheaper than the
same swarm launched at 70–80k, because the 10+ downstream turns the swarm
needs after the last worker finishes (review, rebase, merge, start-next,
respond to questions) each spend ~15–20k on a context that has *kept growing*
throughout the run. **Low at launch = late blow-up = the room you need to land
the last issue cleanly.** Once you're at 150–200k, every merge turn compounds,
and the last 5% of the swarm costs more than the first 50%.

Two levers, in order of impact:

1. **Delegate exploration downward.** You read the issues ONCE. Then any
   exploration that follows — verifying the issue's claims, finding what's
   already landed, grepping the consumer of a unit's output, checking the
   baseline-test count — runs in throwaway worker subagents that return only
   the conclusion. The reading and grepping never tax your window; you build
   the plan on the payloads they hand back.
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
> Read `warp`'s SKILL.md first — its rebase → `--ff-only` merge discipline is
> what `mise run land` mechanises, once per worker branch, and is not repeated
> below. Read `.claude/rules/testing.md` too. [`relay`](../relay/SKILL.md) is
> this skill at wave size 1.

## Harness primitives — what the worker model actually is

The skill is written harness-agnostic; the primitives differ. **Identify your
harness once at the start, then follow that column.** The repo's primary
harness today is **opencode**; the Claude Code column is kept for portability.

| Concern | opencode | Claude Code |
|---|---|---|
| Dispatch tool | `task` (one call per worker, `subagent_type: "drone"` + full brief in `prompt`) | `Agent` with `name` (teammate); brief comes via `SendMessage` in step 2 |
| Parallel | N `task` calls in **one orchestrator message** — they run concurrently, orchestrator blocks until the wave returns | `run_in_background: true` per `Agent` call — they run concurrently, orchestrator keeps working |
| Worker model | `drone` (this repo: `opencode-go/deepseek-v4-flash` @ `reasoningEffort: max`, full tool set incl. `task` for grandchildren) | `sonnet` for code, `haiku` for ultra-mechanical |
| Read-only leaf | `explore` subagent — verified tool set: `bash, glob, grep, read, webfetch` (NO `task`, so it's a true leaf) | `Explore(model=haiku)` — same shape, capped |
| Resume a blocked worker | pass the prior `task_id` to the `task` tool — same session, hot context | `SendMessage` to the live `name` — same session, hot context |
| Worker isolation | worker runs `mise run worktree:new -- <slug>` as its first action, uses absolute paths | **same mise convention** — swarm spawns teammates without `isolation`, so they start in the shared checkout too. Harness `isolation: "worktree"` exists but is not used here (auto-created, auto-reclaimed when the agent exits unchanged — see Gotchas). |
| Inter-worker comms | none — workers can't see each other; orchestrator is the relay | shared task board via `TaskCreate`/`List`/`Update` (teammates only) + `SendMessage` mailbox |
| In-session task board | none — track units in your own session todo list | `TaskCreate` serialized (not parallel — last-write-wins bug verified 2026-07-30) |

**Subagents can nest.** Verified for both harnesses:

- opencode: `drone` and `general` have full tool sets including `task`, so a
  worker can launch its own `explore` grandchild for broad read-only search
  (orientation cost lands in a throwaway context, not the worker's). `explore`
  has no `task` — it's a leaf, deeper nesting buys nothing.
- Claude Code: `general-purpose`/`claude` get the `Agent` tool and can spawn
  `Explore` grandchildren; `Explore`/`Plan` are capped (`Agent` removed).

Tell workers in their brief that they may delegate broad searches downward to
a read-only grandchild when the unit needs "where is X handled across the
repo" — but cap depth at worker → leaf. A grandchild past that is wasted.

**Workers cannot see this conversation, the issue, or sibling units.**
Everything a worker needs — owned paths, acceptance test, "done" definition,
harness-aware escalation channel — goes in its `task` prompt (opencode) or
its `SendMessage` brief (Claude Code). The standing flow rules (worktree
first, hard-stop, explicit-path `git add`, verification caps, report format)
do *not* go in the brief — `drone` carries them, and the brief opens with
`"Invoke the drone skill, then do the following:"`. Leaving the standing
rules implicit because "drone has them" is correct; leaving the *unit
specifics* implicit because "it's in the issue" is the standard way a swarm
goes wrong.

## Gate — do not swarm the wrong work

All four must hold. If any fails, use `warp` instead; a swarm on unsuitable
work costs *more* than doing it yourself, because you pay decomposition + N
merges and still end up reading the diffs.

1. **Pre-decided.** Every design question is already answered — in the issue,
   in a plan you just wrote, or in `docs/`. Workers cannot ask the user
   anything. An issue that floats alternatives ("…or some other way to show
   it") is *not* yet pre-decided: pick one, write it into the worker's prompt
   as settled, and tell the worker not to redesign it. Descope the issue's
   speculative asides ("maybe we can drop the trimming too?") to a `NOTES:`
   line — a second decision must not ride along on a bug fix. Pinning those
   forks is the orchestrator's job; needing the *user* to pin one is what
   fails this gate.
2. **Decomposable into units a worker can hold.** Prefer file-disjoint units —
   they parallelize with clean rebases. But overlap is a **sequencing** fact,
   not a disqualification: two units on one file run in order, and a unit
   blocked on another can ride the same swarm behind it. Maintaining that DAG
   is your job (see §2). What fails this gate is work that won't come apart at
   all.
3. **Mechanical enough for a smaller model**, given red-green instructions: a
   failing test (or an exact spec) defines done.
4. **No human input mid-flight.** If the user must weigh in halfway, the
   swarm stalls with N worktrees open.

5. **You have the budget for it.** A swarm is the most token-expensive thing
   in this repo, and the rate-limit window is the binding constraint — see
   "Size the swarm to the window" below.

Being the strongest available model is itself part of the gate. A weaker
model may drive a swarm only when the decomposition is already written down —
not when it must be derived.

## Size the swarm to the window — do this BEFORE decomposing

Measured 2026-08-03: **one issue costs roughly 10–20% of a fresh rate-limit
window**, depending on size and on how many iterations the drone needs.
Stopping a running worker is **not free** — it costs a turn per worker, and
shedding six mid-flight workers cost ~10% on its own. So the arithmetic has to
happen before dispatch, not after:

> **units × 15% + (workers × 2% shutdown reserve) must fit in what's left.**

**Second measurement, 2026-08-03 — a run that SUCCEEDED** (the numbers above
came from one that didn't). 3 workers, 4 units, one of them a warm worktree
resume, two escalations each resolved in a single message: **~48% of a fresh
window** at the point 3 units were merged and the 4th implemented, with
review/merge/teardown and the knowledge sweep pushing it somewhat past that.
Call it **~12% per unit including all orchestration** — skill load, 4 issue
reads with comments, pre-flight audits, 3 diff reviews, 3 rebase+merges, 4
full-suite runs and board upkeep.

The formula predicted 66% for that shape, so it over-estimates by roughly
1.4×. **Keep the 15% anyway.** It is a deliberate ceiling covering the case a
worker grinds instead of asking, and the cheap run only happened because every
brief capped verification (§4) and because the orchestrator ran the
cross-file audits in its own context rather than paying a drone to search.
Lower the constant and you lose the margin exactly when a run goes badly —
which is when it matters.

You cannot query your own remaining budget, so **ask the user for the number**
if you don't already have it — one question is cheaper than a forced
break-off. Then:

| Window remaining | What that buys |
|---|---|
| < 40% | Don't swarm. Run `warp` on the single highest-value issue. |
| 40–60% | 2 workers, 1 unit each. |
| 60–80% | 3 workers, ~2 units each. |
| > 80% | 4–5 workers. Beyond that you are betting the window. |

**Ten workers is never the answer**, however tempting the backlog looks. A
swarm that hits 100% mid-flight loses every uncommitted unit *and* the turns
needed to shut down cleanly — strictly worse than a smaller swarm that
finishes.

**Prefer landing 4 issues to starting 12.** The user's goal is issues closed,
and an unmerged worktree closes nothing. When in doubt, cut the worker count,
not the per-worker verification — verification is what makes a unit
mergeable.

**A unit that builds a NEW surface is `warp`-sized, not a swarm second unit.**
Measured 2026-08-27: a unit that had to add a new panel scene, a new read
path through a subsystem it did not start out owning, AND a display rule was
clustered as one worker's second issue. It ran to ~400k tokens without
committing and had to be halted; its sibling units, each a bounded change to
existing code, cost a third of that. The tell is in the issue's own file
list — **a unit whose acceptance requires a file that does not exist yet is a
different shape of work** from one that changes files that do.

**But a draft that exists and was merely never *run* is NOT that shape**, even
when it came out of a previous grind. Verified 2026-08-27 on #621: a draft
deferred twice as unverified-new-surface turned out substantially complete, and
its single failing test was a one-line fixture bug. Its own commit message
claimed the work was unfinished and was wrong about itself — a commit message
is a claim, not evidence. The cheap discriminator is `mise run check` plus the
draft's own test, which costs about two minutes and settles it either way. Run
that before deferring anything on novelty grounds. Give it its
own `warp`, or make it the worker's ONLY unit and expect to review it like a
feature, not a fix.

**But an ABANDONED DRAFT is not that shape, and costs two minutes to tell
apart.** Measured 2026-08-27: a unit was deferred out of a swarm as
unverified new surface because a prior session left 575 uncommitted
insertions that had never been compiled or run, and its own commit message
said the hard parts were unfinished. They weren't — the whole display rule
was implemented and tested; one fixture bug (two entities silently sharing a
default faction resource) was masking the only failure. **A commit message is
a claim, not evidence.** When a draft exists, the discriminator is cheap and
mechanical: rebase it, `mise run check`, run its own test file. That tells you
whether you have a near-done unit or a rewrite, before you spend a deferral on
it. The new-surface rule above is about files that *do not exist*; a file that
exists but has never been executed is a different case, and the run is what
settles it.

**Watch worker cost, and halt rather than hope.** Nothing in the harness caps
a worker's spend, and a grinding worker looks identical to a working one from
the orchestrator's seat — in this run the *user* spotted it first. When you
do halt: `TaskStop` the worker (a `SendMessage` costs another turn on a
context that is already the expensive thing), then commit its worktree
yourself as a `wip(...)` commit that states plainly what was never run, write
the state onto the issue, and move the issue OUT of `in-progress`. A halted
unit that is preserved and documented costs the next session nothing; loose
worktree state costs it everything.

## Stop compliance and relief — this applies to you too, not just drones

`drone` carries the context-budget and stop-compliance rules for workers. You
are not exempt — a real orchestrator session violated its own stop
instruction in 48 seconds and manufactured the worst drone of the night doing
it (below). Two separate obligations follow.

### A stop instruction outranks everything you're doing

If the owner tells you to stop, stand down, or hand off, that supersedes
dispatch, review, and merge — all of it, immediately. **Spawning a subagent
is starting new work.** It doesn't feel like an action the way running a test
does, because you aren't touching a file, but a `task`/`Agent` call is
exactly what a stop instruction forbids. Verified failure, 2026-08-27:

| time | event |
|---|---|
| 21:26:05 | owner: "you really need to stop taking turns" — orchestrator at 253k |
| 21:27:38 | owner: "instruct each drone to SendMessage the relief when done… you just close off workers as they finish" |
| 21:28:26 | orchestrator spawns a new worker — **48 seconds later** |
| 21:36:16 | orchestrator spawns another — 10 minutes after the stop, at ~300k |
| 21:41:55 | owner: "relief agent is handling that. stand down." — at 303.8k |

The second worker spawned there ran 260 turns to 319k before being killed —
the compliance failure didn't just waste this session's turns, it
manufactured a second, worse offender.

**The correct response to a stop directed at you is: redirect, then go
quiet.** Message every in-flight worker to `SendMessage`/report to **relief**
(not you) on completion, then take no further action except closing workers
out as they drain. **Put relief's actual address in that message** — from
`ListAgents`, or from the owner — because "report to relief" names nobody a
drone can send to, and a redirect the drone cannot act on leaves you holding
its report anyway, which is the one thing you no longer have the context to
do — no new dispatches, no merges, no test runs, no reviews.
That is the **retiring** state; see `.claude/skills/relief/SKILL.md` for its
full contract and for what relief does with the handover. Issuing that
redirect is your last deliberate act before going quiet.

### Request relief before you degrade — don't wait to be told

- **Request relief at ~180k.** Past this point, plan to hand dispatch,
  review, and merge to a fresh session before you're forced to.
- **Hard stop at 250k: dispatch nothing new, ever**, relief-requested or not.
  250k is where real orchestrators measurably lost track of their own
  in-flight work.
- **Duplicate dispatch is a zero-instrumentation tripwire that overrides
  every number.** If a worker replies "already done" / "I already executed
  this" to a fresh dispatch, you are past your useful context *right now* —
  you have lost track of what you already sent out. Both `tooltip-fan` and
  `participant-id` said exactly this, north of ~250k, in the run above.
- **A manual owner trigger always overrides**, in either direction.

Full detail on requesting relief, the briefing it reads, and the worked
example is `.claude/skills/relief/SKILL.md` — this section is your
obligations as the outgoing side; that skill is what the incoming session
follows.

## The planner fork — a Sonnet lead with an Opus planner (#857)

Whoever spawns the drones eats one wake per drone stop; that is the
structural lever, and in the trial it was an Opus at 150k+. The supported
alternative: **a Sonnet session runs this skill and spawns a short-lived Opus
`planner` subagent** (`Agent`, `model: "opus"`, no `name`, `run_in_background:
false`) that does §1–§2 — reads the issues with comments, runs the probes,
builds the DAG, fences and tier tags, writes one brief per unit to
`docs/handoffs/swarm-brief-<n>.md` (gitignored under `swarm-*.md`) and the
roster into the ledger — and returns. Its context dies with it. The Sonnet
lead then spawns Sage and the drones from those files, receives every stop
cheaply, runs the train gate, pushes, reconciles.

The risk, stated honestly: **mid-run judgement lands on Sonnet** — a blocked
fork, a relief, a drone that disagrees with its issue. Two mitigations, and
they are the whole reason the shape is allowed: Sage exists for exactly that
class of question (drones ask it, not you), and the planner can be re-invoked
as a subagent for a re-plan (hand it the ledger and the question). If a run
is small enough that you are the Opus anyway, be the planner yourself — the
fork is about who pays the wakes, not about ceremony.

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
those by *delegation*, not by reading more yourself. Drop one of these and let
it absorb the context:

- **opencode: one `task` call with `subagent_type: "drone"` (or `"explore"`
  for read-only probes) per question, all in ONE orchestrator message.** They
  run in parallel; you block until the wave returns; you read only the final
  report from each.
- **Claude Code: `Explore` with `model: "haiku"` in parallel**, one per
  question.

Typical probes: "is the seam the issue names actually present in master?",
"has any of this already landed?", "where does X get called from?", "what
tests already exist for this subsystem?", "is the reported baseline flake
real?". They read excerpts and return only the answer.

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

> Have one `task`/`Explore` tabulate, per issue: (a) the literal acceptance
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
worker also costs an idle-notification or wave-roundtrip wakeup). If you find
yourself with six workers, look for the two clusters you failed to merge.

**Within a wave, the file boundary is absolute.** Write each worker's file
list into its prompt as an ownership boundary: *"you own exactly these paths;
if the task seems to need a file you don't own, stop and report it."*

**Every unit carries a tier tag (#857).** `sonnet` is the default — a
Sage-backed Sonnet that lands the same diff with 1–2 exchanges is cheaper
than an Opus at ~50 turns / 200k+. Tag `opus` when the unit has **design
freedom** (a new scene or system, a new surface), **deletes or reshapes >300
lines across modules**, or **carries a fork the issue's comments do not
close**. `haiku` only for pure mechanical churn (rename, mass replace). The
tag decides the drone's `model`, how you review it (§5: `--stat` only on
`sonnet`, full diff on `opus`), and what the ledger logs. The tier fork is
settled on numbers, not now: the ledger's roster logs **per issue**
`model / ctx at report / tool calls / Sage exchanges / findings at review`,
and a Sonnet past **3** Sage exchanges is mis-tiered by definition (Sage
flags it in `LANDED:`). Trial data so far is split — #758 landed Sonnet at
155k with 1 exchange; #764 retired at 250k after 4, but that was two
half-units in one drone, so the datum is per-drone, not per-issue.

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
this: commit before reporting, never rebase, never merge, never touch `master`,
never run `land`). Its commits are the handoff.

**The landing is one locked command: `mise run land -- <branch> [--closes
<n>]`** (`.mise/tasks/land`, #857). It takes the serial merge token (a
`flock` on `.godot/land.lock` — a second caller waits and says so), rebases
the branch onto `master` inside its own worktree, runs `mise run check` plus
`test:dir` for every `test/unit/<dir>/` the branch touches (a rebased tree is
a tree nobody tested), fast-forwards, adds the empty `land: #<n> <slug>`
commit carrying `Closes #<n>`, and moves the board to `in-review`. It refuses
— non-zero, reason on stdout — on a dirty main checkout, a rebase conflict
(aborted, files listed), a red `check`/`test:dir`, or a non-ff. It never runs
the full suite and never pushes.

**Who runs it:** in a Sage run, **Sage**, in the same turn as its `approved`;
you never rebase or fast-forward by hand in a Sage run — if `land` fails,
Sage hands the printed reason to the drone, which resolves in its worktree
and re-asks. Without Sage, you run `land` — from your own cheap context. Do
not message/resume a worker to "rebase and merge your branch" **and do not
have it run `land` either**: the drone's stop already woke you, its resume is
a turn at 150k+, and a second stop wakes you again — strictly worse than the
same command from Sage's already-awake turn or yours. The old rule holds for
the old reason; `land` just moved the dance into one call.

### 3. Dispatch — check the roster, claim the kanban, then fire one parallel wave

**Step 1, before anything else: check the roster.** `docs/handoffs/swarm-<date>.md`
is this run's dispatch ledger — one file, both the briefing and the
at-most-once record. If it doesn't exist yet, create it now, before your
first dispatch. **It is gitignored (`docs/handoffs/swarm-*.md`) and should
stay that way** — you rewrite it on every dispatch, report and merge, which
put 20 commits of pure scaffolding on the 2026-08-28 run before it was
ignored. Write it, never commit it; anything that must outlive the run goes
to the issue, a design doc, or a rule file. Contents:

- A **roster table**: unit / brief file / drone name / tier / state
  (`dispatched@HH:MM` → `reported` → `landed <sha>` | `rejected→redispatched`)
  plus the per-issue metrics (#857): `model / ctx at report / tool calls /
  Sage exchanges / findings at review` — filled from the drone's report and
  Sage's `LANDED:` message. This is the evidence the tier fork is settled on.
- **Unpersisted decisions and swings** — each reduced to a pointer once it
  lands in its real home (issue, doc, rule file), per
  `.claude/rules/handoffs.md`. Never the only place a decision lives.
- **Next steps / queue order.**

**At-most-once dispatch lives in this file, not in your memory.** Checking it
before every dispatch is what makes duplicate dispatch mechanical to avoid
rather than something you have to remember to check for — the
duplicate-dispatch tripwire above is the backstop for when the file is stale
or missing, not a substitute for keeping it current.

**Update it on every dispatch, every report collected, every merge, every
owner call.** Rewrite in place, never append — target ≤ ~1.5k tokens. One
`Edit` per event; the cost is what buys you a cheap `relief` handover later
(`.claude/skills/relief/SKILL.md` reads exactly this file plus
`mise gh-project -- list in-progress` to get oriented). Delete the file once
the run is closed out, per `.claude/rules/handoffs.md`.

**Claim every issue on the kanban before you spawn anything:**

```bash
mise gh-project -- status <n> in-progress    # once per issue, at dispatch
```

This is the *persistent* board (`mise gh-project`), not any in-session task
list. They are different surfaces and only this one survives the session. An
unclaimed issue looks free, so a later swarm (or the user) picks it up and
duplicates the work. Flip it back to `ready` if you dispatch nothing.

#### opencode

**One `task` call per worker, all in a single orchestrator message.** That
is what makes them run in parallel — multiple `task` calls in one message
execute concurrently, and the orchestrator blocks until the wave returns.
The full brief lives in the `prompt` parameter; there is no second step.

```
task({ subagent_type: "drone", prompt: <full brief A> })
task({ subagent_type: "drone", prompt: <full brief B> })
task({ subagent_type: "drone", prompt: <full brief C> })
```

Each brief opens with this line (the isolation guarantee — without it the
worker edits the shared main checkout):

> Run `mise run worktree:new -- <your-unit-slug>` as your FIRST action, then
> use absolute paths into `.worktrees/<slug>/` for everything after. Do not
> edit anything before that worktree exists.

Then: **"Invoke the `drone` skill, then do the following."** (Subagents
inherit the skill list. If a worker reports it can't find `drone`, tell it
to `Read .claude/skills/drone/SKILL.md` instead; it's plain markdown.)

Each worker reports its own `BRANCH:` (the `<slug>` from `worktree:new`).
Record the slugs in your session todo list — they are your merge handles, and
the only way back to a worker's commits.

#### Claude Code

**Dispatch is two steps, and skipping the second stalls the whole swarm.**
A named teammate does *not* run the `Agent` call's `prompt` — it returns
"will receive instructions via mailbox" and sits idle. This is a **field
observation (2026-07-30), not documented behaviour** — the tool description
still presents `prompt` as the task — so if a spawn *does* start working off
its prompt, believe the spawn and skip step 2.

**Passing `name` is what makes an agent a teammate** — and therefore what
costs you the prompt. Easy to add for addressability and silently lose the
task with it. This bites non-worker spawns too: a `claude-code-guide` given a
`name` and a full prompt will sit idle exactly the same way.

**Budget one nudge per worker. Do not mistake the first idle for a fast
finish.** Field observation (2026-08-26, 5/5 workers): after the `SendMessage`
brief arrives, a teammate performs roughly ONE action from it — in every case
the `mise run worktree:new` that led the brief — then emits an
`idle_notification` and stops. It is *not* ignoring the message: the worktree
exists, at the correct tip, before any nudge. A second `SendMessage` ("you went
idle, continue, numbered steps follow") then drives the ENTIRE job unattended —
one worker did two full issues, ~900 lines across 15 files, off a single nudge.

Second data point (2026-08-27): with the dispatch above (placeholder spawn
prompt, full multi-paragraph brief via `SendMessage`), the idle fired 7/7 —
including briefs that explicitly said "do NOT stop after the worktree step;
work straight through unattended." Brief wording inside that shape does not
prevent it.

But a **different dispatch shape avoided it, 2/2**, same session, same day:
write the full brief to a file first, spawn with a one-line prompt pointing
at it ("Read `<path>` and execute it fully, start to finish, without waiting
for further instruction"), then `SendMessage` one line repeating that
pointer. Both workers started immediately, no idle at all. Prefer this
file-pointer shape as the default. Caveat: 2/2 is a small sample and this
was not a controlled experiment — the file-brief shape changes two things at
once (where the brief lives, and how short the spawn prompt is), so which of
those does the work is not established. Keep the nudge below as the
fallback — it is still needed whenever a worker does idle.

So on every idle notification, **check the branch before reacting**: no commits
plus a worktree means nudge, not merge.

**And never infer from an idle notification that a worker's BACKGROUND COMMAND
has finished.** Verified 2026-09-10: an orchestrator saw a worker idle while
waiting on its own `test:dir` run, concluded the run had "already drained", and
nudged it saying so. The worker checked `ps`, found the godot process alive
mid-suite, and correctly pushed back on the orchestrator's premise. A worker
idles when it ends a turn — which is exactly what it is *supposed* to do while a
backgrounded command runs (`.claude/rules/long-running-commands.md`). Treat that
idle as "waiting, correctly", not as "stuck". If you nudge anyway, tell it to
*read its output file once* rather than asserting what the file says. The cause is unsettled — see #595, which
records the two candidates, the verified upstream lineage (`anthropics/claude-code`
#28075, #29163 — both CLOSED, and #29163 is a different API surface), and the
one-line experiment that would settle it (spawn, wait, *then* brief — the only
option that removes the round-trip rather than absorbing it). Do not write the
race mechanism in as fact until that has actually been tried.

**Never acknowledge a finished teammate.** A courtesy "thanks, merged" wakes it
and emits another `idle_notification`, which invites another reply —
`anthropics/claude-code` #85047, still OPEN. When a worker is done, go quiet and
merge. Relatedly, a worker whose report crossed with your nudge will re-report
that it is already finished; that is the same crossing, not a second unit of
work. So:

**Step 1 — spawn every worker in a single message** (that is what makes them
run in parallel). Per `Agent` call:

- **`name`, and NO `isolation` parameter.** Workers are teammates; each
  makes its own worktree via `mise run worktree:new`. Harness isolation
  takes the shared task board away — and a teammate therefore starts in the
  **shared main checkout**, which is why the worktree-first line leads the
  brief.
- `subagent_type: "general-purpose"` (the default if omitted) or `"claude"` —
  both carry the full tool set. Never `Explore`/`Plan`: they have no
  `Edit`/`Write`.
- `model: "sonnet"`, or `"haiku"` for ultra-mechanical work (rename, mass
  string-replace, boilerplate).
- A **minimal** prompt. The real brief comes in step 2; anything here is
  not read. (Backgrounding is the default now; don't pass
  `run_in_background` — named teammates are always async regardless.)

**Step 2 — `SendMessage` each worker its brief.** The first line must be the
same worktree-first line as above. Then `Invoke the drone skill, then do the
following.`

#### Both harnesses — the bare-number brief (#857)

**`"Invoke the drone skill, then do the following:"` and ~15 lines.** The
`drone` skill carries every standing rule — worktree-first, hard-stop,
explicit-path `git add`, verification caps, the report format, ask-Sage-then-
stop. The **issue** carries the spec: the drone reads `gh issue view <n>` and
`gh issue view <n> --comments` itself, at start and again before it asks for
review (drift check — a comment that lands mid-run is the drone's to notice,
not yours to relay). `Ready` means exactly "a drone given only the number, its
comments and a fence can act" (`swarmify`'s criterion); if you find yourself
restating a decision from the issue, the brief is becoming a second spec —
stop. What the brief carries, and nothing else:

- **Issue number(s)** — `#<n>`, plus the parent hub if there is one.
- **Owned paths** — the exact fence. Generic ownership rule is drone's; the
  list is per-unit.
- **Seams** — who else touches what this run: "`#m` (drone `foo`) owns
  `ui/hud/`; the seam is `HudRoot.compose()`, committed on master at `<sha>`."
- **Tier** — `sonnet` | `opus`, and that it decides the drone's model.
- **"Sage is your advisor"** — `SendMessage` to `Sage` for questions and for
  the review before reporting; **never `main`** except for a stop.
- **A turn/time budget.** An explicit ceiling — turns and wall-clock — as an
  independent tripwire (`tooltip-fan` #621 ran 290 turns / 41 minutes before
  being killed; a token-only budget catches that too late).
- **COMMIT EARLY AND OFTEN, even partial** — its own line (an API spend limit
  killed two drones in one minute on 2026-09-10; a budget never fires for
  that).
- **The three suite clauses**, if the unit may earn a full suite at all
  (§3b) — otherwise "never the full suite; Sage lands, main gates".

Acceptance restated, "what done means", file maps, house rules by name,
recent commits to `git show` — **none of it.** That was the thick brief, and
it drifted from the issue every time a comment landed. If the issue cannot
carry it, the issue is not `Ready`; bounce it, don't patch it in a brief.

The one standing rule worth naming in the brief anyway, in one line, is the
**hard-stop escalation channel** — because it differs by harness and the
worker needs to know which one it's in:

- **opencode**: "Stopping with a question in `NOTES:` *is* asking the
  orchestrator. There is no mid-flight backchannel — your `task` call returns
  one report; I resume you via `task_id` with the answer if recoverable."
- **Claude Code**: "`SendMessage` `main` with the specific question and stop.
  Your context stays warm; I reply and you continue." (The tool doc scopes
  `to: "main"` to *background subagents* — teammates qualify, since spawns
  background by default. Verified working both ways, worker → `main` and
  `main` → worker by name.)

That distinction is not in `drone` (it picks the right channel from its
harness table) — but naming it here costs one line and prevents the worker
from inventing a channel that does not exist in its harness.

**`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is on.** It is set in this user's
`~/.claude/settings.json` (confirmed 2026-08-05) — treat that as given and
**never spend a turn checking it**: no `echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`,
no `grep` of settings. It is read at launch and cannot be enabled
mid-session, so a check can only tell you something you can't act on. The one
case worth handling is a spawn that *actually* comes back without teammate
behaviour — deal with it then, reactively.

### 3b. Token economy — the binding constraint, and how to actually respect it

**Measured, one run, three workers each doing two units:**

| Worker | Tokens | Tool calls | Notes |
|---|---|---|---|
| cheapest | 147k | 64 | clean run, no escalation |
| middle | ~197k | 65 | one escalation + one forced worktree move |
| dearest | 199k | 93 | ran the full suite repeatedly + `xvfb` shader boots |

The spread tracks **tool calls, not units of work.** The dearest worker did
the same amount of code as the cheapest and cost 35% more, entirely in
verification it was never asked for. That is the lever.

**Bound verification explicitly in every prompt.** Drone already carries the
ladder (`check` → `test:one` → `test:dir` → full, ~215s for the full suite as
of 2026-08-28) and the cap that goes with it — full suite **at most once**,
at final green, never to explore, never per edit; no new test harnesses
unless the brief names one; no `xvfb` unless a shader changed. Adding a
one-line reminder in the brief is cheap insurance; restating the full bullet
list is drone's job and wastes tokens. The lever itself is real: the dearest
worker in the run below cost 35% more than the cheapest for *identical
code*, entirely in verification it was never asked for.

**Three clauses about the suite, not two — the third is the one you'll drop.**
Every brief must say: *launch it once with `run_in_background: true`*; *then do
nothing — no sleep, no tail, no ls, no re-reading the output file*; *then END
YOUR TURN with no further output.* On 2026-09-08 a brief carried clauses one
and three and the worker still polled ~a dozen times until the owner killed it
mid-run. They are independent, so paste all three verbatim — correcting a
worker mid-run re-derives its whole context and costs more than the polling
did. `.claude/rules/long-running-commands.md` is the always-on crumb, and the
same rule binds **you**: an orchestrator polled its own gate ~12 times the
same day.

**Have workers delegate broad searches downward too, not just you.** When a
unit needs "where is X handled across the repo", drone already tells the
worker to spawn a read-only grandchild (opencode: `task` with
`subagent_type: "explore"`; Claude Code: `Explore(model=haiku)`) and cap depth
at worker → leaf. You don't need to instruct it again in the brief — just
trust the skill. The savings are real: the orientation cost lands in a cheap
throwaway context instead of the worker's, and nesting is confirmed permitted
in both harnesses.

**Plan for running out — and note that the window is not the only thing that
can kill a worker.** Verified 2026-09-10: two workers were terminated
mid-flight by an **API spend limit**, with no warning to them or to the
orchestrator, in the same minute. One had committed its finished unit and lost
nothing; the other had committed nothing and would have lost everything, and
was saved only because the orchestrator went into its worktree and committed
the tree by hand. **Put "COMMIT EARLY AND OFTEN, even partial, even ugly" in
every brief as its own line** — not as a consequence of the budget rule, since
an external kill ignores budgets entirely.

When a worker does die, **check its worktree before assuming the unit is
lost**: `git -C .worktrees/<slug> log master..HEAD` plus `git status
--porcelain`. In that run one issue was already committed and merged as-is, and
the other's entire working set — including both `.uid` sidecars — was sitting
untracked on disk and needed only `git add` by explicit path. Then verify it
yourself rather than paying a fresh drone to reload the context: a killed
drone's work is a *claim of incompleteness*, and that claim is often wrong (that
unit turned out complete and correct; `check` plus its own test file settled it
in two minutes — the same discriminator the abandoned-draft rule above
prescribes).

Assume the window may close mid-swarm, and make that survivable:

- Workers commit **after each unit**, never only at the end. A killed worker
  then loses one unit, not two.
- Merge each branch as it lands. Do not batch *merging* to the end — four
  merged units beat six unmerged ones. (This is about survival, not
  verification: the authoritative *suite* runs once per batch of merges, a
  separate and still-correct cadence — see §6's merge train.)
- When a worker dies mid-unit, **commit its uncommitted worktree state
  yourself** as an explicit `wip(...)` commit that says what is unfinished,
  and write the blocker onto the issue. Never leave work as loose worktree
  state, and never leave the issue `in-progress` with nobody on it.

### 4. Collect — act on each completion as it lands

**Review and merge-decision happen as each report lands, not batched to the
end** — that is what "do not batch" means here, and it is a different batch
from §6's: this one is about *your attention*, not about *when the suite
runs*. Letting five reports pile up before you look at any of them is the
mistake this heading warns against; running one suite over a train of
already-reviewed merges is not that mistake — see §6.

`drone` mandates a terse structured report. Read those, not the diffs. If a
worker's report is a wall of text, that's a `drone` violation — don't
propagate it into your summary to the user.

**How you act on completions depends on the harness:**

- **opencode — wave-based.** The `task` tool is synchronous; an orchestrator
  message with N `task` calls blocks until the whole wave returns. So you
  review each returned report in turn, act on it (merge / fix-then-merge /
  resume / abandon), and only when the wave is fully processed do you
  dispatch the next wave. You cannot interleave "merge drone-1 while
  drone-2 keeps typing" — that's the one thing Claude Code's backgrounding
  buys you and opencode does not. Mitigation: fewer, fatter workers; the
  wave roundtrip tax argues for 2–3 workers, not 6.
- **Claude Code — per-completion.** Backgrounded workers report via
  `idle_notification` as they finish. Act on each report the moment it lands
  — review the diff while the other workers keep typing. That diff is
  harvested at peak freshness and never re-read.

For each worker report, run this decision tree (same for both harnesses):

```bash
git -C .worktrees/<slug> log master..HEAD --stat   # scope first
git diff master...<branch> --stat                  # what files it touched
git diff master...<branch>                         # then content
```

1. **Ownership check.** Did it touch only its owned paths? If it strayed into
   a file outside its boundary, that's a bug to understand *before* you read
   the content — either the worker guessed wrong (resume-and-redirect) or
   your boundary was wrong (fix the boundary, restate the unit, merge is
   fine).
2. **Content check.** Reads as the spec asked? No quiet cop-outs (a feature
   silently descoped, a thing removed "because the test was hard", a TODO
   left where the issue asked for code)? Compare against the
   acceptance-parameters table from §1a — if the worker added an escape
   that the issue spec rejected, push back.
3. **Test check.** A drone's own green — down to a `test:dir` run — is
   acceptable input to proceeding with the merge; it is a claim, not the
   verdict. The verdict is your own **authoritative full suite**, run once
   per **batch** of merges rather than after every individual fast-forward
   (the merge train, §6) — never the worker's claim standing in for it.
   **A narrow `test:dir` green says nothing about fallout outside that
   directory**, and the drone cannot know what it missed: a change to a
   default, a constant, or an eligibility rule is read by tests that never
   import the file it edited. Cheap pre-empt when writing the brief —
   `grep -rn "<the old value>" test/` — and expect stale *characterization*
   tests, which get re-pointed onto the new invariant rather than deleted (one
   may have lost its subject entirely). See `.claude/rules/testing.md`.

Then **branch on quality**, in decreasing order of frequency:

- **Perfect — land it now.** In a Sage run this branch is Sage's, not
  yours: Sage approved and ran `mise run land` in the same turn, so the
  drone's stop is the *only* thing you receive — check `--stat` for the
  fence (§5), note the report's numbers in the ledger, and move on. Without
  Sage: `mise run land -- <branch> --closes <n>` from your own context (§6).
  Do not let it sit. The authoritative suite runs once per train, not on
  this individual landing.
- **Almost perfect — fix it yourself, then merge.** The diff is 95% right and
  the gap is a one-line thing the worker would burn a full escalation round
  to arrive at. You are the smart model and the cheap context — make the
  edit in your window, then merge. Spending a worker turn on a
  resume-then-re-review is *more* tokens than the fix itself.
- **Badly done but recoverable — resume the drone.** opencode: pass the prior
  `task_id` to a new `task` call with a sharp diagnosis and the specific
  re-direction. Claude Code: `SendMessage` the same agent `name`. In both
  cases the worker's session/context is still alive; continuing it is far
  cheaper than a cold respawn and it keeps the unit's accumulated reading
  hot. State clearly what was wrong and what the new target is — the
  orchestrator is the source of wisdom here, not a passive reviewer.
- **Genuinely stuck — stop, do not grind.** A worker that reports the same
  blocker twice after a resume, or surfaces something that is plainly a real
  design fork the user must settle, is not solvable by more drone turns. Move
  the issue to `in-review` on the kanban with a one-line comment naming the
  fork, and **focus on the remainder of the swarm.** Do not let one
  unsolvable unit stall the merge queue for the other six.

A worker that reported a blocker (needed a file it didn't own; test won't go
green; ambiguity in the spec) on its *first* report has done the right thing
under the hard-stop rule — escalate it to "almost perfect" / "badly done"
paths above. The blocker itself is signal, not a failure of the worker.

### 5. Review

**Sage is THE reviewer for `sonnet`-tier units; you read `--stat` only.**
`.claude/agents/sage.md` is a persistent Fable advisor + reviewer + lander
teammate: spawn one at dispatch (`Agent` with `subagent_type: "sage"`,
`name: "Sage"`, backgrounded; its spawn message carries only the run-specific
part — issues, DAG, seams, tiers, roster) and every brief says "Sage is your
advisor; ask it for a review BEFORE you report." Drones' questions and
reviews land on Sage's context, Sage runs `land` on `approved`, and your
per-unit read is:

```bash
git diff master...<branch> --stat     # sonnet tier: the fence check, and that is all
git diff master...<branch>            # opus tier / design units: the full diff, yours
```

The token premise of the whole shape depends on this: the trial's lead read
every diff *with* Sage present and still finished at ~180k. A Sonnet-tier
unit gets one reviewer, Sage; an Opus-tier or design unit (new scene, solver
cut, anything a player would notice) gets two — Sage first, then you on the
full diff. **Routing is one recipient per message, never both:** the drone's
review request goes to Sage; its report is its final turn text (the
completion notification brings it to you — never tell a drone to
`SendMessage main` on top); Sage's one `LANDED:` message per run comes at the
end. **The gate is `land`, not a `REVIEW` line:** a unit Sage has not
approved cannot have been landed by Sage, and `master` moving by exactly that
branch is the evidence — reconcile at §6. Trial 2026-09-11 (6 drones, up to
4 concurrent, owner absent): 4 reviews, 5 real findings all acted on, one
laundered owner quote caught, one gameplay gap missed (now in Sage's
mandate), one 26-minute drone stall while Sage ran a sibling's audit, two
units merged unreviewed under the per-unit `REVIEW` protocol; the lead
finished at ~180k. Verdict: net positive at 4+ concurrent drones or an
absent owner; below that, be the reviewer yourself and run `land` yourself.

Without Sage: you are the reviewer for every tier, the `--stat` first and the
content second, and nothing lands unreviewed.

**Do not accept a worker's claim that a failure is pre-existing.** Two
workers in one run reported "975/976, the failure is a pre-existing baseline
flake, confirmed by stashing my changes." Both were wrong: their baseline
included a *sibling worker's* commit that had landed in the shared worktree.
`master` was green at 976/976 the whole time. Check the baseline yourself
with a real `master` run — it is one command, and it is the difference
between merging a genuine regression and not.

The regression in that case was in the orchestrator's own pre-dispatch seam,
and only became reachable once a worker implemented the first real override
of it. **Expect your seam's bugs to surface at merge, not when you wrote it.**

A green suite proves the worker's *mechanism*, not the *outcome*. That gap is
widest on visual work: a z-index assertion fully determines draw order, but
no assertion tells you a semitransparent band is legible on screen, and a
shader that compiles can still render nothing. When a unit changes what the
game looks like, either drive it (`mise run play`) or say plainly
to the user that you confirmed the plumbing and not the pixels. Don't let
"tests pass, shader compiles" quietly stand in for "it looks right".

### 6. Land, one branch at a time — but test once per train

Per branch, in sequence: `mise run land -- <branch> [--closes <n>]` — the
rebase-inside-its-worktree, `check` + `test:dir`, `--ff-only` dance of
`warp` step 6 as one locked call (merge contract, above). Sequential is not a
limitation — the `flock` enforces it, and each rebase re-tests the *next*
branch against the landed result of the previous ones, which is the only
place a cross-unit break surfaces. **In a Sage run, Sage runs it and you
never rebase by hand;** what stays yours, always: the full suite once per
train, the push, and the reconcile — Sage's `LANDED: #n <sha>, …` against
`git log master`, one line per unit, every sha present and nothing on
`master` that no `LANDED:` entry claims.

**The authoritative full suite runs once per batch of merges, not once per
merge.** Owner call, 2026-08-28: *"orchestrator holds all the cards, if they
merge in 10 commits… then merge all then test once."* Fast-forward every
branch in the batch first, **then** run `mise run test` once against the
merged tip. `swarm-v2` ran 11 authoritative suites in one night doing it
per-merge; a train cuts that to roughly 2–4.

**On a red batch, bisect.** Re-run the suite (or the narrower `test:dir` for
the failing area) against successive merge points until you isolate the
offending branch — that costs ~log2(n) extra suite runs, paid only in the
failure case, and is still cheaper than paying the full 215s on every merge
whether or not anything ever breaks.

**The suite is a gate on code, not a ritual owed to every train.** "Once per
batch" replaces "once per merge" — it does not mean "always." A batch that
touched no `.gd`/`.tscn` (a docs-only or skills-only train, say) cannot be
observed by a 215s Godot test run at all; running one anyway is the same
mistake this whole cluster tells a *drone* not to make, just committed by the
orchestrator instead. Match the check to what actually changed: `mise run
check` if any script changed, the full suite once the batch is runtime-
observable, and no Godot test at all for a documentation-only batch.

If the units were file-disjoint, every rebase is clean. A conflict here
means the decomposition leaked — fix the decomposition's consequence, not
just the conflict.

**Closing the issue(s).** Workers never write `Closes #<n>` themselves —
`land --closes <n>` adds it as an empty `land: #<n> <slug>` commit on top of
the fast-forward (it cannot amend the drone's tip), and only the *last*
branch for an issue gets the flag, because only the planner knows which one
that is — say so in the DAG and in Sage's spawn message:

- **One issue, N units** — `--closes` on the *final* branch's land only. Not
  on the others: whichever landed first would close the issue while the rest
  of the work is still in flight.
- **N independent issues** — `--closes` on every land, each naming its own
  issue. Every branch is the last one for its issue.

`Closes` fires on **push**, not on the local fast-forward. So merging does
not close anything. Check `git status -sb` before you claim an issue is
done, and remember `master` may carry unrelated commits (yours, or another
agent's) that a push would ship alongside your work — surface that and let
the user decide.

Because the close is deferred to the push, `land --closes` moves the issue
to `in-review` as it lands, so the board reflects reality even though the
issue is still open (it prints a ⚠ if the board call failed — then by hand):

```bash
mise gh-project -- status <n> in-review     # branch landed on master, awaiting push
```

If a worker reported a blocker and stopped, put the issue back to `ready` (or
`backlog`) with a comment saying what blocked it — never leave it
`in-progress` with nobody on it. A stuck `in-progress` is the one state that
silently blocks the next swarm.

### 7. Teardown

**Teardown is yours and unconditional — once the worker is actually done.** A
merged branch is not the same as a finished worker: the worker may still be
running its own final verification in that worktree after you've already
fast-forwarded its commits into `master`. Tear down only once it has reported
and you do not intend to resume it. Symptom of getting this wrong: a worker
that looks hung is often mid-command against a worktree path you just
deleted, not stuck.

A `mise` worktree is *never* auto-removed — the point, so a stopped worker can
be resumed into its own checkout — but it means every worker leaves one
behind, whether or not it committed.

```bash
mise run worktree:ls                                # find the survivors
mise run worktree:rm -- <slug>                      # fuzzy-matches; per worker
git branch -d <slug>                                # -d, not -D: refuses if unmerged
```

Both plain forms work on a merged worker branch — reach for `--force` / `-D`
only once you know why the plain one refused. `remove` refuses while the
worktree is still `locked` or dirty; `branch -d` refuses when the branch
isn't in `master`, which means you dropped a worker's work. Neither is a
formality to `--force` past.

<details>
<summary>Claude Code: harness worktrees live elsewhere and reclaim differently</summary>

- **Worker worktrees live under `.claude/worktrees/agent-<id>/`, on branch
  `worktree-agent-<id>`** — not under `.worktrees/`, and not from
  `mise run worktree:new`. The harness creates them, branched from
  `master`'s tip at spawn time, and returns the path and branch in the
  tool result. That's the substrate; `mise`'s worktree tasks are for
  `warp`'s single-checkout cycle.
- **Resuming a worker that stopped clean can drop it into ANOTHER worker's
  worktree.** The harness reclaims an `isolation: "worktree"` worktree
  when its agent exits without changes. `SendMessage` then resumes that
  agent from its transcript — but with no worktree of its own, and it can
  land in a *sibling worker's* checkout. Observed: a worker stopped to
  ask a question, was resumed with the answer, and committed onto another
  live worker's branch while that worker's uncommitted WIP sat in the
  same tree. Nothing errored.

  The blast radius is real: one `git add -A` there would have committed
  half of another agent's unfinished work.

  **Before resuming any Claude Code worker that reported and stopped,
  create it a fresh worktree** (`git worktree add
  .claude/worktrees/agent-<name>-2 -b <branch> master`) and name the
  absolute path in your message. Tell every worker to `git add` **by
  explicit path, never `-A` or `-a`** — that is the standing mitigation,
  since you will not always notice the swap. If a stray commit does land
  on the wrong branch, leave it: if it is file-disjoint it merges fine
  from there, and telling a deep-context worker to disentangle git
  history is the most expensive possible fix.

This does not apply to opencode: it has no harness worktrees, only `mise`
ones, so there is no reclaim-and-land-in-sibling bug surface.

</details>

## Gotchas

### A worker's green run does not transfer — refresh the class cache after you land

If a worker introduced a new `class_name`, it ran `mise run refresh` **in its
own worktree** and went green there.
The main checkout has its own `.godot/`, so right after your cherry-pick master
fails with `Could not find type "X" in the current scope` — plus a cascade of
"Parse error" / "Cannot infer the type of …" from every file that touches it.
Nothing is wrong with the diff; the cache is stale. Refresh it on master, then
re-run.

That refresh is also what generates the `.uid` for a worker's new test file,
so until you run it **GUT silently does not collect the new test** — the
suite looks green at the *old* script count. Compare `Scripts` / `Tests`
totals before and after; if the totals didn't move, the new test never ran.

**The `.uid` can also be generated but never *staged*, which looks identical.**
A worker that ran `refresh` in its own worktree has the `.uid` on disk, so the
test collects there and its report is honest — but if the worker staged only
the `.gd`, the `.uid` stays untracked and the file is invisible in every other
checkout. This is silent in both directions: green in the worktree, green on
master, just one script short. Check `git status` in the worker's worktree for
an untracked `.uid` beside every new test file, and commit it. Verified
2026-08-27 on #627, caught only because the merging orchestrator compared
script counts.

Per `.claude/rules/godot-workflow.md`, an editor pass re-serializes scenes
it touches, and master is a shared checkout that may carry the user's
uncommitted WIP. `mise run refresh` is the whole check — it excludes
pre-existing dirt and hands back a verdict. Don't `md5sum` or stage copies.
Restore anything non-default it flags; ignore id and position noise.

### Workers branch from `master` as it was when they spawned

Merging branch A moves `master`; branch B is now behind. That's why step 6
rebases each branch immediately before its own merge, not all of them up
front.

### A worker's context is not yours

It cannot see this conversation, the issue, or the sibling workers' units.
Everything it needs goes in its prompt: the files it owns, the acceptance
test, and what "done" means.

### Relay, don't paste

The whole point is your context stays small. Summarize worker reports for
the user in your own words; a swarm whose orchestrator pastes N diffs has
spent its context anyway and saved nothing.

### Always `git -C <path>`, never bare `git` after a `cd`

Bash's working directory persists across tool calls. `cd` into a worktree to
run its tests and every later `git` command silently targets *that* worktree
— a `merge --ff-only` aimed at master will cheerfully report "Already up to
date" while merging a branch into itself. Nothing errors. Spell out the
repo path on every git call.

### A worker's fresh worktree cold-imports and dirties tracked `.import` files

`git rebase` then refuses with "cannot rebase: You have unstaged changes."
Run `git -C <worktree> checkout -- .` first. Same for the main checkout
after a real-backend (`opengl3`) shader check — it re-imports every
texture.

### `master` can move under you mid-swarm

Another agent may land commits in the shared main checkout while your
workers run. That's fine — it's why step 6 rebases each branch immediately
before its own merge — but *re-read `master`* before concluding a merge
misbehaved.

### Untracked files in the main checkout are invisible to worktrees

A test count taken there won't match a worker's. Compare tracked-only
totals, and when a count is off, `git ls-files --error-unmatch <path>`
before suspecting a worker. A file present in the main checkout's suite but
absent from every worktree's is almost certainly untracked, not deleted by
a worker.

### `git add` by explicit path, never `-A` or `-a`

Across both harnesses a worker can land in the wrong checkout (Claude Code
transcript-resume bug) or just make a sloppy stage. Explicit-path `git add`
keeps the blast radius bounded. This is `drone`'s standing rule — don't
undercut it.