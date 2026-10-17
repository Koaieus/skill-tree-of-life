---
name: swarm
description: >-
  Orchestrate parallel `drone` subagents over `Ready` issues — hold the DAG,
  dispatch one fenced unit per drone in its own worktree, review each report as
  it lands, land it with `mise run land`, gate the train once, push. Use when
  the user says "swarm #<n>" / "swarm #<n>, #<m>" or asks to parallelise
  pre-decided work across subagents. `relay` is this at wave size 1; `relief`
  takes a running swarm over.
---

# Swarm

Why each step says what it says: `docs/charters/swarm.md`.

You are the lead. You do three things nobody else can — **hold the DAG**,
**gate the train**, **decide** (tier, fence, merge / resume / abandon) — and
spend your context on nothing else. Reading, grepping, typing and verifying
are delegated downward. Stay low at launch: every page you read is re-read
at every later wake, and the last unit is landed on what is left.

## 1. Gate — is this a swarm at all?

1. Five tests, all must hold: **pre-decided** (every design question is
   answered on the issue — it is `Ready`, or it is not swarmed),
   **decomposable** (units a drone can hold), **mechanical** (a failing test
   or exact spec defines done), **unattended** (nobody needs the owner
   mid-flight), **affordable** (the budget of step 3 fits). Any failure →
   `warp` the single highest-value issue instead.
2. A unit that **builds a new surface** — a file its acceptance needs that
   does not exist — is a whole-issue unit, opus-tier, reviewed like a
   feature. A draft that exists but was never run is not that: `mise run
   check` plus its own test file, two minutes, settles which.
3. **Three or more deliverables in one unit is a split**, done now, never
   left to a drone. Size net at dispatch: a unit expected to exceed ~40
   calls or ~120k context is split before it goes out.

## 2. Orient

One Bash call before anything else:

```
mise run ledger -- show
mise gh-project -- list
git -C <repo> worktree list
ls .claude/worktrees/
```

- **Mode.** If the launch prompt says *train mode, train `<t>`*, read
  section 10 before anything else; it changes dispatch, reporting and the
  ledger handle. Otherwise this is a standalone swarm.
- **Draining check on any resume** — a drone's wake, a bare `continue`
  after a cut-off: the first read is the ledger (`mise run ledger -- show`;
  in train mode `cat "$SWARM_LEDGER"`). A `## Draining` section means you
  are draining for the rest of your life: spawn no drone, land each kept
  unit's report as it arrives, resume a kept unit's own drone by
  `SendMessage` only to finish it, treat every other unit as the relief's.
  A resume line is never an instruction to dispatch.
- **Stray worktrees** (`mise run worktree:ls`; `.claude/worktrees/`
  included): delete, do not carry as a question, once the branch is merged
  or nothing in it is worth mining. Check first: `git -C .worktrees/<slug>
  log master..HEAD` + `status --porcelain`.
- **Shared contracts land on master first.** A seam every unit overrides, a
  registry every unit appends to, a `.tres` every unit touches — commit it
  before spawning; drones branch from the tip.
- Read each issue as `gh issue view <n> --comments`. A `Ready` issue carries
  its reading list, seam map and stubs; dispatch from it directly. A
  throwaway Opus planner subagent that writes the DAG and briefs and dies is
  the fallback for a run whose issues are not that well specced — and the
  fix for next time is a better `swarmify` pass.

## 3. Plan the wave

- **Workers: 2–5, never ten.** Land four issues over starting twelve.
  Cluster by shared context first (one drone, several units, hot context),
  partition by file second; fewer drones wins.
- **Price the wave.** Ask the owner for the remaining window as one figure.
  Per-unit cost is the ledger's number: the last run's `mise run agent-cost`
  `priced` per landed unit, tier-adjusted. No fixed percentage.
- **Tier.** Default opus. Sonnet only for a small unit with an existing
  named test, or mechanical churn where rigor buys nothing. A Sonnet that
  spends its stuck call, or `PULL`s on something that was not a fork, is
  logged as a mis-tier.
- **Dispatch ceiling** = ceiling(model) − 15k × drones in flight, read on
  the hook's `CONTEXT SIZE` marker: 250k for a Sonnet lead, 200k for an
  Opus lead. Past the ceiling, dispatch nothing new. **Request relief 50k
  below it.** A drone replying "already done" to a dispatch overrides every
  number: you are past your useful context now.
- **Sage is opt-in and never lands.** At four or more concurrent drones, or
  an absent owner, spawn one `sage` agent named "Sage" as reviewer and
  advisor; drones then ask Sage instead of `advisor`. Sage's `approved`
  goes back to the drone, which carries it in its report; you land off the
  report. Sage messages you only for exceptions (a second failed land, a
  cross-unit conflict, a mis-tier) and one `REVIEWED:` list at the end.
  Not in train mode.
- **Trap list for a genuinely hard unit** (a bit-exact transliteration, a
  solver port, anything a green suite would not catch): `ListAgents`, then
  ask an idle peer for *where this will break* — not a plan, not a file
  summary — and (1) which files it holds so the drone stays clear; say "if
  you're mid-task, answer (1) alone". Dispatch without waiting; relay the
  list verbatim into the brief when it arrives. Anything the peer marked
  *unverified* goes to the drone as an open question to resolve by reading,
  never as fact.

## 4. Dispatch

**Before every dispatch, one Bash call** — the ledger row, the kanban
claim, the drift check:

```
# train mode: export SWARM_LEDGER=<path from the launch prompt> first, on this and every ledger/land call
{ [ -n "${SWARM_LEDGER:-}" ] && grep -q '^## Draining' "$SWARM_LEDGER" \
  || mise run ledger -- show | grep -q '^## Draining'; } && echo DRAINING && exit 0
mise run ledger -- dispatch <n> <drone-name> <tier>     # creates the file on a new run; prints the roster back
mise gh-project -- status <n> in-progress
mise run issue-drift -- <n>
```

- The ledger (`docs/handoffs/swarm-<date>-<HHMM>.md`, gitignored, ≤1.5k
  tokens) is the at-most-once record and the relief briefing. **Its roster
  is written by commands, never by you remembering**: `ledger -- dispatch`,
  `ledger -- report`, `land` write the rows; `ledger -- note <n> '…'`
  appends to a row's notes without touching its state. Always `mise run
  ledger -- show`, never a path built from a date. Its handle is your
  session lineage: `/swarm` always starts its own run; another live ledger
  on disk is never a relief trigger — the verb decides relief (`/relief`
  runs `ledger -- adopt`). The run ends with `ledger -- close`. The prose
  under the roster (queue order, carried items, open owner calls) is yours.
- `issue-drift` is silent when the stamped reading list holds, prints the
  drifted entries otherwise — then one `Explore(model: "haiku")` re-verifies
  them before the brief is written — and says `no stamp` on an unstamped
  issue.
- **The `Agent` call**: brief in `prompt`; `name` for addressability;
  `subagent_type: "drone"`; `model` **mandatory and equal to the ledger's
  tier**. No `isolation` parameter — the drone makes its own `mise`
  worktree. If a drone idles on its prompt: one `SendMessage` nudge, then
  the file-pointer brief is the fallback shape; `ledger -- note` the idle.
- **One wave per message.** All `Agent` calls for a wave in one message;
  act on each completion as it arrives, never batch reports.
- **A split shares one brief file.** Splitting one issue across drones:
  write `docs/handoffs/swarm-brief-<n>.md` (gitignored), common part first,
  one short section per drone; each `prompt` is the file path plus its
  section name; the file's first line says whether the issue is still the
  spec (a split of a `Ready` issue: it is) or the brief replaces it (the
  planner shape).
- A second brief of a collision pair names the first's landed sha.

### The brief — bare

```
Unit: #<n> (hub #<h>). Branch from master tip <sha>.
Fence (yours alone): <paths — including every scene / board that references the changed system>
Seams this run: <who owns what, each seam's sha>
Tier: <opus|sonnet>
Your advisor is the `advisor` tool.      # or: "Sage is your advisor (SendMessage to Sage)"
  Plan: after orientation, before your first edit.
  Stuck: at most once — when you can no longer say what you believe is wrong
    and what the next attempt will show. A typo or a wrong path is not stuck.
  Done: before you report, ask it to review your diff.   # omit when Sage runs
  If the unit hits an unresolved fork or a wall, its answer is "stop — report PULL": do that.
Budget: HARD stop at <N> calls to your FIRST report — do not take call N+1. Each
  review round after that: +<k> calls, two rounds at most.
Commit early and often, even partial.
Suite: <one of>
  never the full suite — `mise run check` and `test:one` / `test:dir` only
  | the full suite: once, only after `test:dir` is green; in the background, then
    END YOUR TURN (the harness resumes you on exit); report its verdict line.
    # train mode: the middle clause becomes "in the foreground, timeout 600000"
Trap list: <peer's list verbatim, unverified items marked as questions>   # only if one was asked for
```

Nothing the issue already says; nothing the drone already carries. **Never
open `.claude/agents/drone.md`** — this is the digest. A `drone` already:
makes its own worktree (`mise run worktree:new -- <slug>`) before any edit;
reads the issue once, writes only owned paths, reads anything; `git add`s by
explicit path, never stashes, never lands, never writes `Closes #n`; writes
a named test RED first and confirms it ran, and authors no test for an
exact-spec / visual / tuning unit; holds "pre-existing failure" as a claim
and notes it; has a coherent commit by ~150k, retires on a blown budget
with a successor brief on the issue, never finishes past the stop; calls
the `advisor` tool only when the brief names it, never the user; defaults
an open number as a knob, not a doubt; batches shell commands, never polls
or idles, verifies on the ladder `check` → `test:one` → `test:dir`; ends
its turn with its report as its final text and is spent once it has
reported. The report is exactly this:

```
BRANCH: <slug>
FILES: <paths touched>
TESTS: <what ran, what is green>
DID: <one line>
COST: ctx <k>, calls <n>, exchanges <n>
NOTES: <follow-ups, poison: lines, Sage approved N exchanges, PULL>
```

Six lines; a `PULL` or a stuck stop rides in `NOTES:`. A wall of text is a drone-contract violation, not something to
summarise.

## 5. Collect

- **Read reports, not diffs.** `COST:` is the drone's own count — use it to
  judge resume vs retire and to tier the next brief without waiting for
  `agent-cost`.
- **Per report, in one Bash call**: `mise run ledger -- report <n> --branch
  <slug> [--plan] [--stuck] [--pull]`, then `git -C .worktrees/<slug> diff
  --stat master..HEAD` for the fence.
- **Fence, content, tests — then branch.** One of five: land it; fix a
  one-liner yourself, then land; resume the drone with a sharp diagnosis;
  pull it — a `PULL` or a fork → `mise gh-project -- status <n>
  needs-design`, and what it blocks is not dispatched; or stop — the same
  blocker twice with no fork → `in-review` with a one-line comment — and
  serve the rest of the swarm.
- The full diff only where the cross-unit overview is what is checked (a
  shared seam, anything a player would notice); a drone's done-call
  reviewed the rest. One `advisor` call per wave for the judgement, not
  per unit.
- **"Pre-existing failure" is a claim.** Check against a real `master` run
  — `mise run test:one -- <script>` in the main checkout — before landing
  over it.
- **Never acknowledge a finished drone.** Never infer from an idle that a
  drone's background command finished. Relay reports in your own words,
  never paste diffs.
- **A killed drone's worktree is checked before it is written off**: `git
  -C .worktrees/<slug> log master..HEAD` + `status --porcelain`; commit what
  is there by explicit path as `wip(...)`; the two-minute discriminator of
  step 1.2 decides done vs rewrite.
- **A stop from the owner outranks everything, including spawning.** Go
  quiet — no dispatch, no merge, no test, no review. If a relief session
  has named itself, owe it exactly one wake per in-flight drone: on each
  report, update that drone's ledger row and `SendMessage` relief one line.
  Never redirect a drone to relief's address.

## 6. Land

- **`mise run land -- <branch> [--closes <n>]` is the only way onto
  master**, from your own cheap context. Serial by `flock`; rebases in the
  worktree; runs `check` + `test:dir`; writes the `landed <sha>` ledger row
  itself. `--closes` only on the final branch of a multi-unit issue.
- Its verdict is the exit code or a `LANDED` / `✗` line — filter with
  `grep -E 'LANDED|✗|ERROR'`, never on success alone.
- A non-zero is handed back to the drone once; twice is a stop.
- Never resume a deep-context drone to rebase, merge or land.

## 7. Sweep follow-ups — the board is the last resort

Before the gate — a sweep drone's branch is part of the batch it gates — sweep every `poison:` line and `NOTES:` follow-up:

1. One-liners: apply yourself in the main checkout as one docs commit.
2. Anything bounded and mechanical — a doc row, a rename, a prune, a missing
   twin test, a stale comment, a `.tres` that should exist; no design
   question, a drone-unit or less — goes to **one sweep drone** appended to
   the train, same branch discipline as any unit.
3. Only a genuine fork, an owner call, or work past a drone-unit earns an
   issue, filed through the `spec` skill; it stays in `Intake`, its fork
   written as a menu. Never a "follow-ups from swarm" grab-bag.

## 8. Gate the train

- **The full suite runs once per train**, after every branch of the batch is
  fast-forwarded, and only when the batch is runtime-observable (`.gd` /
  `.tscn` changed): `mise run test` with `run_in_background: true`, end the
  turn (train mode: foreground, `timeout: 600000`). `check` for a
  scripts-only batch; nothing for docs. Red train → bisect by `test:dir` on
  merge points.
- **After a new `class_name` lands, compare script counts** across the
  train's suite run: a missing or unstaged `.uid` is a test that silently
  never ran. No hand `refresh` — `mise run test*` refreshes the cache itself.
- `git -C <repo> push origin master`. **`Closes` fires on push.** Then `mise gh-project -- hygiene --fix`
  once. A blocked unit goes back to `ready` with a comment; never
  `in-progress` with nobody on it.

## 9. Teardown and report

- **Tear down only a drone that has reported and will not be resumed**:
  `mise run worktree:rm -- <slug>` then `git branch -d <slug>` (never `-D`
  until you know why `-d` refused).
- **Sweep your run's worktrees before the final report.** `mise run
  worktree:ls`, then per worktree `git -C <path> log master..HEAD` +
  `status --porcelain`. **Your own** (a branch a drone of yours reported, or
  `.claude/worktrees/agent-<id>` with one of your subagents' ids): landed →
  remove; dropped or killed → keep only if something is worth mining
  (committed `wip(...)`, named in the report), else remove. **Anything else**
  with nothing ahead of `master` and a clean tree: remove too — but only if
  no other lead is live (a fresh drone of a relief or sibling looks exactly
  like that). A draining lead sweeps at its final report, not at
  `relief now`.
- Always `git -C`, never a bare `git` after a `cd`; explicit-path `git
  add`; `checkout -- .` a worktree that cold-imported before rebasing;
  re-read `master` before concluding a merge misbehaved — it moves under you.
- `mise run ledger -- close`.
- **The run ends with the session report** (`docs/domain/session-report.md`):
  one row per unit under `Landed`; the step-7 sweep rendered as
  `Follow-ups`, each with a disposition — *fixed now* or *a drone did it*
  before *filed*; `Not done` counts every worktree left, one line each with
  why. Fill the ledger's `adv` / ctx / calls / priced from `mise run
  agent-cost` (your own session via `--main`); every landing's `cost:` rows
  are at `scratchpad/land/land-<n>.log`.
- A lesson this skill does not say is posted where it is learned: `mise run
  feedback -- post swarm <kind> <file>`.

## 10. Train mode

The launch prompt says *train mode, train `<t>`: #… — ledger `<whip path>`
— swarm ledger `<path>`*. You are a `swarm-lead` subagent; your parent is
the train's top session, not a person. Train mode is the only unattended
mode; the top carries the transport. Every other step holds; these change:

- **Ledger handle.** Every lead in the tree shares the top's session id, so
  the session lookup is never used: `export SWARM_LEDGER=<swarm ledger
  path>` on **every** `ledger` and `land` call — a bare call lands in
  whichever lead's file is newest. A relief's prompt names the dead
  outgoing's file to read and its own to write; nothing is `adopt`ed; the
  whip ledger path is read, never adopted. A unit with a row in any other
  live ledger — a draining lead's included — is never dispatched.
- **`mkdir -p <inbox>/done` (absolute path) before the wave.** Then drones
  go out in the background: one message per wave, every `Agent` call
  `run_in_background: true`. Every brief ends with three acts, in
  order:
  ```
  Final act, in order: (1) write the six-line report to
  <abs path>/docs/handoffs/swarm-<date>-<lead-name>.inbox/<unit>.md;
  (2) SendMessage(<lead-name>, <the same report>); (3) the report as your final text.
  ```
  The drone's `SendMessage` is what wakes you. Act per drone; a second wake
  for a unit already handled is nothing.
- **Nothing else in the tree backgrounds a command.** Gate suite and `land`
  run in the foreground (`timeout: 600000`); every brief's suite clauses
  swap the middle one — *in the foreground, `timeout` 600000* replaces *in
  the background, then END YOUR TURN*; never a backgrounded suite.
- **Nap, do not end the turn, while any row is in flight**:
  ```
  until [ -n "$(find <inbox> -maxdepth 1 -name '*.md' -print -quit)" ]; do sleep 20; done
  ```
  with `timeout: 600000`. On every return (file or cap) read the inbox;
  move a handled file to `<inbox>/done/`; on a cap return with no file,
  check drones by `ListAgents`. A wake whose body is not the six-line
  report gets one `SendMessage` to continue — never a transcript poll or
  `pgrep` wait. End the turn only when no row is in flight. A lead that
  slipped out of its nap ends on the one line `interim: <n>/<m> landed, <k>
  in flight`.
- **Sage is out**; drones' advisor is the `advisor` tool.
- **Relief threshold is your own context** (step 3's ceiling, relief 50k
  below), never the train's size. The moment the context notice lands:
  1. write a `## Draining` section into your swarm ledger's prose —
     `relief asked <HH:MM>; I keep <unit list>` — so it is on disk first;
  2. `SendMessage` the top: `relief now; I keep <unit list>`;
  3. dispatch nothing more; land each kept report as it arrives; `mise run
     ledger -- close`; return the session report as your final text.
  The top launches the relief. A relief dispatches beside the draining lead
  up to the cap minus the outgoing's `dispatched` rows; when only blocked
  units remain it ends its turn on `blocked on <outgoing>` until the top's
  `drained` line wakes it.
- **The owner's stop** arrives as a message from the top and drains when
  your nap returns, ten minutes at most.
- **A drone that ends without its final act is silent — you are the first
  net.** `ListAgents` shows it `completed` or `killed` with no inbox file:
  treat it as a failed unit yourself — the step-5 killed-drone worktree
  check, `mise run ledger -- note <n> 'ended without report'`, then
  re-dispatch or retire. The top's stall tick is only the second net.
- **Report by returning** the session report as your final text.
