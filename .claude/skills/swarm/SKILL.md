---
name: swarm
description: Orchestrate parallel `drone` subagents over `Ready` issues — hold the DAG, dispatch one fenced unit per drone in its own worktree, review each report as it lands, land it with `mise run land`, gate the train once, push. Use when the user says "swarm #<n>" / "swarm #<n>, #<m>" or asks to parallelise pre-decided work across subagents. `relay` is this at wave size 1; `relief` takes a running swarm over.
---

# Swarm

You are the **DAG holder**, the **reviewer and lander**, and the **train
gate**. Drones do the typing, each in its own worktree and context; you
decide — tier, fence, land / fix / resume / abandon — and you spend your
context on nothing else. Reading, grepping and verifying are delegated
downward, always. Why each rule below exists: `docs/charters/swarm.md`.

## What a drone already carries — never in a brief

Never open `.claude/agents/drone.md`; this is all of it you need. A drone
makes its own worktree (`worktree:new`, warm and checked); reads the issue
and `--comments` once as its spec (a `swarm-brief-*.md` says on its first
line whether it replaces the issue or only adds a section to it);
`cat`s the repo skill the issue names; searches via `Explore(haiku)` leaves;
batches, reads narrow, never polls; runs `check` → `test:one` → `test:dir`
→ the full suite at most once and only if the brief allows; commits as it
goes by explicit path (a new script's generated `.uid` included), the red
test first when a claim is testable; writes
only owned paths and reports a need outside the fence instead of reaching;
`@export`s an open number as a knob and lists it as tentative; calls
`advisor` at the plan, once when stuck (out of hypotheses, not a count of
failures), and at done when there is no Sage; reports `PULL` on a fork or
a wall; retires on a blown budget by `wip(...)` commit + successor `gh issue comment` + report; never
`Closes`, rebases, lands, asks the user, or expands scope.

Its report is six lines — `BRANCH:` (your merge handle) / `FILES:` /
`TESTS:` / `DID:` / `COST:` (ctx · tool calls · advisor/Sage exchanges) /
`NOTES:` (`none`, or one line each: blocker, deviation, stale spec,
out-of-scope, tentative knob, `poison: <path>:<line> — <wrong> → <right>`,
`PULL — <fork>`;
anything a future worker needs is also on the issue). With Sage, the
report's `NOTES:` carries the review round and the drone is spent.

## Gate — do not swarm the wrong work

All five must hold, else `warp` the single highest-value issue instead:

1. **Pre-decided** — every design question is answered on the issue. It is
   `Ready`, or it is not swarmed. Never pin a fork in a brief.
   `Ready` is the whole test — a missing milestone is board hygiene, never a
   reason to hold it back.
2. **Decomposable** into units a drone can hold. Overlap between units is a
   sequencing fact, not a disqualifier.
3. **Mechanical** — a failing test or an exact spec defines done.
4. **Unattended** — nobody needs the owner mid-flight.
5. **Affordable** — the budget below fits.

**A unit whose acceptance needs a file that does not exist is a whole-issue
unit**, opus-tier, reviewed like a feature — never a drone's second unit. A
draft that exists but was never run is *not* that shape: `mise run check`
plus its own test file settles it in two minutes; run that before deferring
anything as "new surface".

**A unit describing three or more deliverables is split before dispatch.**
Never hope a drone self-splits. Sizing was swarmify's job; your net at
dispatch is **a unit expected to exceed ~40 calls or ~120k context is split
before dispatch** — a unit that looks like it needs the whole budget will
blow it.

## Size the swarm

- **2–5 drones, never ten.** Prefer landing four issues to starting twelve.
- **Cluster by shared context first, partition by file second.** Issues that
  read the same subsystem are one drone doing several units with hot
  context; overlap *inside* a drone is free, overlap *across* drones is a
  wave boundary. Fewer drones wins.
- **Per-unit cost is the ledger's number**, not a constant: ask the owner for
  the remaining window as one figure, and price the wave from the last
  run's `mise run agent-cost` `priced` per landed unit at the tier you are
  dispatching. Your own session is priced by `mise run agent-cost -- --main`
  (add `--session` for you plus your drones on one table).

## Hard units: a trap list first

For a bit-exact port or solver transliteration, ask an idle peer (`ListAgents`)
for *where this will break* and which files it holds; dispatch without waiting
and relay the list verbatim into the brief. Unverified items go to the drone as
questions to resolve by reading.

## Your own budget

- **Dispatch ceiling = ceiling(model) − 15k × drones in flight**, read on the
  hook's `CONTEXT SIZE SO FAR` marker. Ceiling is **250k for a Sonnet lead,
  200k for an Opus lead**; every in-flight drone reserves ~15k for its
  settling turns (report, review, land — three turns, not ten). Past the
  ceiling, dispatch nothing new.
- **Request relief 50k below the ceiling** (`.claude/skills/relief/SKILL.md`
  is what the incoming session follows).
- **Duplicate dispatch overrides every number.** A drone replying "already
  done" to a fresh dispatch means you have lost track of what you sent —
  stop dispatching now.
- **A stop from the owner outranks everything, including spawning** — an
  `Agent` call is new work. Go quiet: no dispatch, no merge, no test, no
  review. If a relief session has named itself, you owe it exactly one wake
  per in-flight drone — on each report, update that drone's ledger row and
  `SendMessage` relief one line (`#<n> reported @<sha>, row updated`).
  Never redirect a drone to relief's address; its report reaches you and
  your ping is the relay.

## Roles

- **Drones' advisor is the `advisor` tool**, named in every brief with its
  three moments: the plan (before the first edit), stuck (once — out of
  hypotheses, not a count of failures), and done (only with no Sage: it
  reviews the diff so you don't have to). Its answer is the straight route
  or "stop, report `PULL`".
- **A `PULL` report takes the unit off this run.** Comment the fork on the
  issue, move it to `Needs design`, and don't dispatch anything it blocks;
  a dependent whose spec the fork changes goes back to `Needs design` too.
- **You review and you land.** `git diff master...<branch> --stat` for the
  fence on every unit; the full diff only where your cross-unit overview
  is what's being checked — a seam another unit touches, anything a player
  would notice — since the drone's done-call has reviewed the rest. One
  `advisor` call per wave for the judgement, not per unit. `mise run land` from your own context — never resume a
  deep-context drone to rebase, merge or land.
- **Sage is opt-in, and never lands.** At four or more concurrent drones,
  or an absent owner, spawn `Agent(subagent_type: "sage", name: "Sage")`
  as reviewer and advisor; briefs then say "Sage is your advisor" instead.
  A drone's review request is its last turn: it messages Sage and ends with
  its report as text, and is spent. Sage sends findings to the drone and
  `APPROVED #n <sha>` to **you** — the drone's notification is your fence
  check, Sage's line is your land trigger; never nudge a drone for a
  report and never wake one that Sage approved. `NOT APPROVED` after two
  rounds is yours: resume the drone (hot context) or dispatch fresh. Sage
  otherwise messages you only for exceptions and one `REVIEWED:` list.
- **A throwaway Opus planner is a fallback**, for a run whose issues are not
  well enough specced to dispatch from directly: `Agent(model: "opus",
  run_in_background: false)` writes the DAG, tiers and briefs to
  `docs/handoffs/swarm-brief-<n>.md` and dies. The fix for next time is a
  better swarmify pass, not a standing planner.

## Whip relay mode

Active only when your launch prompt says *whip relay, train `<t>`*. There
is no supervisor session and no human awake: your three human-facing
moments become three verbs, and the verbs pass the baton. This section and
the `CLAUSES` string in `.mise/tasks/whip` (pasted into your launch prompt)
are one contract, two readers — a difference between them is a bug, not a
nuance.

- **Report by verb, one call each**: `mise run whip -- relieve-me` where
  this skill says "request relief" (it launches your relief; you drain per
  `relief`); `mise run whip -- done <pushed sha> <landed n/m>` after the
  push and `hygiene --fix` (it launches the next train's lead, or ends the
  run and renders the report — then end your turn and do nothing more);
  `mise run whip -- needs-owner <n> "<one line>"` *after* you moved the
  issue to `Needs design` with a dated comment stating your assumption or
  the fork — then keep going with the rest of the run. The verbs know your
  train from your session; you never name it.
- **Never ask.** Anything you would have put to the owner is answered by
  your own stated assumption (ledger + issue comment), or the unit is
  pulled. Ending a turn on a question stalls the night.
- **No other traffic**: no progress pings, no messages to anyone. The
  only instructions you receive are the watchdog's prompts (a window
  reset: continue from your ledger) and the owner's stop (go quiet, let
  in-flight drones report, land what is reported, then `done`).
- Everything else in this file is unchanged, the owner-stop rule included.

## The cycle

### 1. Read the issues once, delegate the rest

`/swarm` always starts its own run: the verb decides relief, never the
disk. A ledger is keyed by its lead sessions, so `mise run ledger -- show`
prints yours or says you have none — another lead's live ledger in its list
is not yours to orient from or touch, and your first `ledger -- dispatch`
creates your own. Relief is only `/relief` (`.claude/skills/relief/SKILL.md`),
which joins a ledger with `ledger -- adopt`.

```bash
gh issue view <n>            # once per issue
gh issue view <n> --comments # once; empty output on a 0-comment issue is normal
```

Never re-read; never page through other issues for context. Every
verification — is the seam present on `master`, has any of this landed,
where is X called from, what tests exist — goes to `Explore` agents with
`model: "haiku"`, one per question, all in one message, returning
conclusions only.

For a bulk swarm, have one such agent tabulate per issue: the literal
acceptance bullets, sibling linkage, and anything that smells like a quiet
descope. That table is your approval pass; a descoped spec is pushed back to
the owner, never inherited into a brief.

### 2. Build the DAG, then units

1. Cluster issues by subsystem → that is your drone list.
2. Check file-disjointness *between* clusters; sequence overlapping clusters
   into waves. Wave 2 dispatches from the `master` tip after wave 1 lands.
3. **Tier every unit**: `opus` default for anything medium or larger — a
   new scene, system or surface, a reshaping across modules, any fork the
   comments leave open, or simply >150 lines of expected diff; `sonnet` only
   for small or dumb units — ≤150 lines with a named test that already
   exists, or mechanical churn where rigor buys nothing; `haiku` only for
   pure mechanical churn with nothing to decide. Priced per landed line, opus
   is the cheaper tier on medium units, so the default is not the
   cheap-looking model. A Sonnet that spent its stuck call, reported `PULL`
   on a non-fork, or passed three Sage exchanges is logged as mis-tiered,
   and the next brief is tiered from that.
4. **Shared contracts land on master first.** A seam every unit overrides,
   a registry every unit appends to, a `.tres` every unit touches: commit
   it in the main checkout, test it, then spawn — drones branch from the tip.
5. **Pre-flight envelopes against real content** when units fill a layout
   you own; delegate the measurement.

If the work will not come apart, that is a real answer: `warp`.

### 3. Dispatch — one Bash call, then one message

**Before every dispatch, in a single Bash call:**

```bash
mise run ledger -- dispatch <n> <drone-name> <tier>     # writes the roster row, prints the ledger back
mise gh-project -- status <n> in-progress               # claim on the persistent board
mise run issue-drift -- <n>                             # silent = the Ready comment still holds
```

- **The ledger** (`docs/handoffs/swarm-<date>-<HHMM>.md`, gitignored — never
  commit it; `mise run ledger -- show` finds yours by your session id) is what relief reads. **Its roster is written by commands**:
  `ledger -- dispatch` here (it creates your ledger on your first dispatch,
  its header's `Lead sessions:` line naming you, and prints the whole ledger,
  so you never `cat` it), `ledger -- report` at collect
  (step 4), and `mise run land --closes <n>` writes the `landed <sha>` row
  itself. A row is unit / drone / tier / state (`dispatched@HH:MM` →
  `reported@` | `pulled@` → `landed <sha>`; a re-dispatch says
  `redispatched@`) / PLAN / STUCK / PULL (the advisor's three moments) /
  adv / ctx / calls / priced (from `agent-cost`) / notes (`--note '…'` on
  any write, or `ledger -- note <n> '…'` alone, state untouched). Below the roster, the queue order, carried items and open
  owner calls are your prose: ≤ ~1.5k tokens total. `ledger -- close` at
  teardown archives it; anything that must outlive the run goes to the issue.
- **`issue-drift`** prints nothing when the issue's stamped reading list and
  seam map still hold on `master`; prints the drifted entries otherwise —
  then one `Explore(model: "haiku")` re-verifies *those entries* before you
  write the brief; prints `no stamp` on an issue promoted before stamps
  existed — dispatch as before. It never fails the chain.
- Flip an issue back to `ready` if you end up dispatching nothing for it.

**Then spawn every drone of the wave in one message.** Per `Agent` call:

- `subagent_type: "drone"` — never `Explore`/`Plan` (no `Edit`), never
  `general-purpose` (no drone contract).
- `model:` **mandatory, equal to the ledger's tier.** Read it back against
  the roster row before sending; an omitted `model` silently runs sonnet.
- `name:` — the drone's address for a nudge or a resume.
- **No `isolation`** — the drone makes its own worktree with
  `mise run worktree:new` and reports its `BRANCH:` slug, your merge handle.
- **The full brief in `prompt`.** If a drone idles without starting, one
  `SendMessage` with the same brief; if idles recur, write the brief to a
  file and spawn with a one-line pointer instead. Log every idle in the
  ledger: `mise run ledger -- note <n> 'idle'` (notes only, state untouched).
- **A split shares one brief file.** Splitting one issue across drones:
  write `docs/handoffs/swarm-brief-<n>.md` (gitignored) — first line "the
  issue is still your spec" (or "this brief replaces the issue"), then the
  common part once, then one short `## <drone-name>` section per drone.
  Each `prompt` is the path plus its section name. The common part is the
  bare brief below; a section holds only what differs (fence, seam sha).

**The bare brief** — ~15 lines, only what the issue cannot know:

- **Issue number(s)**, plus the hub if there is one.
- **Owned paths** — the exact fence, *including* scenes, boards and sandbox
  panels that reference the changed system (the seam map on the issue lists
  them).
- **Seams this run** — "`#m` (drone `foo`) owns `ui/hud/`; the seam is
  `HudRoot.compose()`, on master at `<sha>`." For a collision pair, the
  second brief names the first's landed sha.
- **Tier**, and that it decides the drone's model.
- **"Your advisor is the `advisor` tool: at the plan, once when stuck, and
  at done."** (Drop "at done" when Sage runs.) (Or "Sage is your advisor;
  your last turn is the review request to Sage plus your report as text —
  never wait for its verdict.")
- **A turn/time budget as a HARD stop, budgeting the first report**: "80
  calls / 40 minutes to your first report — do not take call 81. Each
  review round after it gets +15 calls; two rounds, then hand back." One
  number for the whole unit is a fiction once a reviewer asks for changes.
- **"COMMIT EARLY AND OFTEN, even partial, even ugly"** — its own line.
- **Suite policy**: either "never the full suite" or, if the unit earns one,
  all three clauses verbatim — *launch it once with `run_in_background:
  true`; then do nothing — no sleep, no tail, no re-reading the output
  file; then END YOUR TURN.*

Acceptance restated, "what done means", file maps, `git show` tours, or
anything from the digest above — none of it. If the issue cannot carry it,
the issue is not `Ready`: bounce it, don't patch it in a brief.

### 4. Collect — act on each report as it lands

Read the six-line report, not the diff. A wall of text is a drone-contract
violation; do not propagate it. **The exact cost is available at report
time, not just at land**: put `mise run agent-cost -- --branch <slug>` in
the same Bash call as the fence `--stat` below — the transcript exists while
the drone is alive — and decide resume / retire / fresh drone on that row.
The report's `COST:` line is the drone's own tally, a cross-check for when
the transcript match fails; `land` prints the row again as the audited
figure for the ledger's `priced` — and persists it, `cost:` rows included,
at `scratchpad/land/land-<n>.log` in the main checkout (#920), so a later
ledger pass never has to re-grep a console that's already scrolled away.

Per report, in order:

```bash
git diff master...<branch> --stat        # 1. fence — every tier (+ agent-cost --branch, same call)
mise run ledger -- report <n> --branch <slug> [--plan] [--stuck] [--pull] [--note '…']   # the row, from the report's COST:/NOTES:
git diff master...<branch>               # 2. content — shared seam / player-visible only
```

`--plan` / `--stuck` are read off the report's `COST:` exchanges and
`NOTES:` (a drone that called its advisor at the plan; one that spent its
stuck call); `--pull` on a `PULL` report. The row's ctx / calls / adv /
priced come from the transcript.

1. **Fence.** Strayed outside its paths? Understand why before reading
   content: the drone guessed (resume-and-redirect) or your fence was wrong
   (fix the fence, land).
2. **Content.** As the spec asked, no quiet cop-out — a feature descoped, a
   TODO where code was asked, an escape the issue rejected.
3. **Tests.** A drone's green is a claim. "Pre-existing failure" is a claim:
   check it against a real `master` run before landing over it. A narrow
   `test:dir` says nothing about fallout outside the directory — expect
   stale characterization tests when a default or constant changed.

Then branch, most frequent first:

- **Land it now** — `mise run land -- <branch> [--closes <n>]`.
- **One-line gap** — fix it in your own context, then land. Cheaper than a
  resume-and-re-review.
- **Recoverable** — `SendMessage` the drone by name with a sharp diagnosis
  and the new target; its context is still hot.
- **Pulled** — a `PULL` report or a real fork you found yourself: the
  `PULL` handling under Roles, then serve the rest of the swarm.
- **Stuck** — the same blocker twice after a resume, no fork: move the issue
  to `in-review` with a one-line comment naming the blocker. A blocker reported on a *first* report is the
  drone doing the right thing; the blocker is the signal.

**A drone that died** (spend limit, kill): check its worktree before writing
the unit off — `git -C .worktrees/<slug> log master..HEAD` and `status
--porcelain`; commit what is there by explicit path as `wip(...)` stating
what was never run; the two-minute discriminator from the gate decides
done vs rewrite. Never leave loose worktree state or an `in-progress` issue
nobody is on.

Never acknowledge a finished drone — a "thanks" wakes it and invites a reply.
Never infer from an idle that a drone's *background command* finished; it
idles correctly while a suite runs.

### 5. Land, one branch at a time — test once per train

`mise run land -- <branch> [--closes <n>]` is the only way onto `master`:
serial by `flock`, rebases inside the drone's worktree, runs `check` +
`test:dir` for the dirs the branch touches, fast-forwards, moves the issue to
`in-review`, derives the hub. Non-zero → hand the printed reason to the
drone once; a second failure is a stop. `--closes` only on the *final*
branch of a multi-unit issue; on every branch of independent issues.
Filter its output with `grep -E 'LANDED|✗|ERROR'` — a red land prints `✗`
and `ERROR`, and a success-only filter shows it as silence.

**Before the gate, sweep `poison:` lines** out of the reports (`ledger --
note <n> 'poison: …'` keeps them findable): apply
the one-liners yourself in the main checkout as one docs commit; anything
that is not a one-liner → `gh issue create` (it joins the board by itself).

**The authoritative suite runs once per train**, after every branch of the
batch is fast-forwarded — and only when the batch is runtime-observable:
`mise run test` if `.gd`/`.tscn` changed, `mise run check` for scripts-only,
nothing for a docs-only train. Red train → bisect with `test:dir` on the
merge points. Launch the suite backgrounded and end your turn.

**After a new `class_name` lands, compare script counts** before and after
the train's suite run: a `.uid` that was never generated, or generated but
never staged, is a test that silently never ran, and no cache predicate sees
it. The cache itself needs no hand `refresh` — `mise run test*` refreshes it
when the `class_name` set drifts.

`Closes` fires on push. `git status -sb` before claiming anything is done;
`master` may carry others' commits a push would ship — surface that. After
the push: `mise gh-project -- hygiene --fix` once.

### 6. Teardown

Only for a drone that has reported and will not be resumed — it may still be
running its final check in that worktree.

```bash
mise run worktree:ls
mise run worktree:rm -- <slug>
git branch -d <slug>          # -d: refuses if unmerged, which means you dropped work
```

A stray worktree (`.claude/worktrees/` too) whose branch is merged, or that
holds nothing worth mining, is deleted on sight — never an owner question.

`mise run ledger -- close` — it moves your ledger to `docs/handoffs/archive/`;
whip never closes it for you. Relay reports to the user in your own words — never paste
a diff.

## Standing gotchas

- **Always `git -C <path>`**, never a bare `git` after a `cd` — a
  `--ff-only` aimed at master will merge a branch into itself and report
  "already up to date".
- **Explicit-path `git add`**, never `-A`/`-a`; never `git stash`.
- A fresh worktree cold-imports and dirties `.import` files: `git -C
  <worktree> checkout -- .` before a rebase complains.
- **`master` moves under you** — another session may land while you run;
  re-read it before concluding a merge misbehaved.
- Untracked files in the main checkout are invisible to worktrees; compare
  tracked-only test counts, `git ls-files --error-unmatch <path>` before
  suspecting a drone.
- The same long-running-command rule binds you: launch the gate once,
  backgrounded, end the turn.
