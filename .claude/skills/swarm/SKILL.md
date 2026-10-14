---
name: swarm
description: 'Orchestrate parallel `drone` subagents over `Ready` issues — hold the DAG, dispatch one fenced unit per drone in its own worktree, review each report as it lands, land it with `mise run land`, gate the train once, push. Use when the user says "swarm #<n>" / "swarm #<n>, #<m>" or asks to parallelise pre-decided work across subagents. `relay` is this at wave size 1; `relief` takes a running swarm over.'
---

# Swarm

You are the orchestrator. The three things only you can do — and the only
things you spend context on — are **hold the DAG**, **gate the train**, and
**decide** (tier, fence, merge / resume / abandon). Reading, grepping, typing
and verifying are delegated downward. Why each step says what it says:
`docs/charters/swarm.md`.

A fresh session always starts its own run: `/swarm` never adopts a ledger it
finds on disk — another live ledger is not a relief trigger, the `/relief`
verb is.

## 1. Gate every issue

Swarm only what passes all five; any failure means `warp` the single
highest-value issue instead.

1. **Pre-decided** — every design question is answered on the issue. It is
   `Ready`, or it is not swarmed.
2. **Decomposable** — the work comes apart into units a drone can hold.
3. **Mechanical** — a failing test or an exact spec defines done.
4. **Unattended** — nobody needs the owner mid-flight.
5. **Affordable** — the budget of step 3 fits.

Then size each unit:

- **A unit that builds a new surface** — a file its acceptance needs that
  does not exist — is a whole-issue unit, opus-tier, reviewed like a
  feature. A draft that exists but was never run is *not* that: `mise run
  check` plus its own test file, two minutes, settles which.
- **Three or more deliverables in one unit is a split**, done before
  dispatch, never left to a drone. Keep a **size net** at dispatch: a unit
  expected to exceed ~40 calls or ~120k context is split before it goes
  out; a unit that already looks like it needs the whole budget will blow
  it.

## 2. Orient from disk, not from issues

One Bash call:

```
mise run ledger -- show
mise gh-project -- list
git -C <repo> worktree list
ls .claude/worktrees/ 2>/dev/null
```

- `ledger -- show` says "none" for a fresh session — expected; `dispatch`
  creates the file. Never build a ledger path from a date.
- A stray worktree (`.worktrees/` or `.claude/worktrees/`) is **deleted, not
  carried as an owner question**, once its branch is merged or nothing in it
  is worth mining: `mise run worktree:rm -- <slug>` then `git branch -d`.
- Always `git -C <repo>` (the main checkout's absolute path), never a bare
  `git` after a `cd`.

## 3. Budget the run

- **Workers: 2–5, never ten.** Prefer landing four issues to starting
  twelve. Cluster by shared context first (one drone, several units, hot
  context), partition by file second; fewer drones wins.
- **Per-unit cost is the ledger's number.** Ask the owner for the remaining
  window as one figure; price the wave from the last run's `mise run
  agent-cost` `priced` column per landed unit, tier-adjusted. No fixed
  percentage. A window percentage is a snapshot, never a comparable unit.
- **Dispatch ceiling = ceiling(model) − 15k × drones in flight**, read on
  the hook's `CONTEXT SIZE` marker: 250k for a Sonnet lead, 200k for an
  Opus lead. Past the ceiling, dispatch nothing new. **Request relief 50k
  below it.** A drone replying "already done" to a dispatch overrides every
  number: you are past your useful context now — request relief.
- **Tier default is opus.** Sonnet only for a small unit with an existing
  named test, or mechanical churn where rigor buys nothing. A Sonnet that
  spent its stuck call, or `PULL`ed on something that was not a fork, is
  logged as a mis-tier (`ledger -- note`).

## 4. Choose the roles

- **The drone's advisor is the `advisor` tool**, named in every brief with
  its three moments:
  - **Plan** — after orientation, before the first edit. Always.
  - **Stuck** — at most once, and stuck is a state, not a count: the drone
    can no longer say what it believes is wrong and what the next attempt
    will show. A typo or a wrong path is not stuck.
  - **Done** — only when no Sage runs: the advisor reviews the diff instead
    of you reading it. It sees only the drone's context, so you still check
    what spans units.
  Its answer is one message: the straight route, or "stop — report `PULL`"
  on an unresolved fork or a wall. A `PULL` takes the unit off the run and
  back to `Needs design`; what it blocks is not dispatched.
- **You review and land.** Never resume a deep-context drone to rebase,
  merge or land.
- **Sage is opt-in and never lands.** At four or more concurrent drones, or
  an absent owner, spawn one `sage` named "Sage" as reviewer and advisor;
  drones then ask Sage instead of `advisor`. `approved` goes back to the
  drone, which carries it in its report (`NOTES: Sage approved, 2
  exchanges`), and you land off that report. Sage messages you only for
  exceptions (a second failed land, a cross-unit conflict, a mis-tier) and
  one `REVIEWED:` list at the end. Sage runs nothing that mutates the repo.
  Not in train mode (section *Train mode*).
- **The planner is a fallback, not a shape.** A `Ready` issue already
  carries its reading list, seam map and stubs; dispatch from it directly.
  Only when the issues are not that well specced, spawn one throwaway Opus
  planner that writes the DAG and the briefs and dies.

## 5. Land shared contracts first

A seam every unit overrides, a registry every unit appends to, a `.tres`
every unit touches — commit it on master yourself before spawning; drones
branch from the tip. The second brief of a collision pair names the first's
landed sha.

## 6. A trap list for a genuinely hard unit

For a bit-exact transliteration, a solver port, anything where a green suite
would not catch the wrong answer: `ListAgents`, then ask an idle peer session
for *where this will break* — not a plan, not a file summary — and (1) which
files it holds so the drone stays clear. Say "if you're mid-task, answer (1)
alone". Dispatch without waiting; relay the list verbatim into the brief (a
`SendMessage` to the drone if it arrives after dispatch). Anything the peer
flagged as *unverified* goes to the drone as an open question to resolve by
reading, never as fact.

## 7. What a drone already carries — never restate it

You never open `.claude/agents/drone.md`. A `drone` already:

- makes its own worktree (`mise run worktree:new -- <slug>`) before any
  edit — pass no `isolation` parameter;
- reads the issue once, writes only owned paths, reads anything;
- `git add`s by explicit path, never stashes, never lands, never writes
  `Closes #n`;
- writes a named test RED first and confirms it ran; authors no test for an
  exact-spec / visual / tuning unit;
- holds "pre-existing failure" as a claim and notes it;
- has a coherent commit by ~150k, retires on a blown budget with a
  successor brief on the issue, and never finishes past the stop;
- calls the `advisor` tool only when the brief names it, never the user;
- defaults an open number as a knob, not a doubt;
- batches shell commands, never polls or idles, verifies on the ladder
  `check` → `test:one` → `test:dir`;
- ends its turn with its report as its final text — a drone is spent once it
  has reported.

The report is six lines, nothing else:

```
BRANCH: <slug>
FILES: <paths touched>
TESTS: <what ran, what is green>
DID: <one line>
COST: ctx <k>, calls <n>, exchanges <n>
NOTES: <follow-ups, poison: lines, Sage approved N exchanges, PULL>
```

A wall of text is a drone-contract violation, not something to summarise.

## 8. Dispatch

### Before every dispatch — one Bash call

```
mise run ledger -- dispatch <n> <drone-name> <tier>
mise gh-project -- status <n> in-progress
mise run issue-drift -- <n>
```

- The ledger (`docs/handoffs/swarm-<date>-<HHMM>.md`, gitignored, ≤1.5k
  tokens) is the at-most-once record and the relief briefing. **Its roster
  is written by commands, never by you remembering**: `dispatch` creates it
  on a new run and prints the roster back, so the read is free. The prose
  under the roster (queue order, carried items, open owner calls) is yours.
- A row before dispatch is the claim: a unit with a row in another live
  ledger is never dispatched.
- `issue-drift` is silent when the issue's stamped reading list still
  holds; it prints the drifted entries otherwise — then one
  `Explore(model: "haiku")` re-verifies them before the brief is written —
  and says `no stamp` on an unstamped issue.

### The brief is bare

Nothing the issue already says, nothing the drone already carries (section
7). Exactly:

```
#<n> (hub #<h>). <one line of what, if the issue title is not enough>
Owned paths: <the fence — including scenes and boards that reference the changed system>
Seams this run: <who owns what; the seam's sha on master>
Tier: <opus|sonnet>
Your advisor is the `advisor` tool: plan after orientation, stuck at most once, done before you report.
   (or: Your advisor is Sage — SendMessage "Sage"; ask it for a review as your final exchange.)
HARD stop: your first report by call <N>; do not take call N+1. Each review round adds <k> calls; two rounds at most.
Commit early and often, even partial.
Suite: never the full suite.
   (or, if a full suite is allowed, all three clauses: once, only after test:dir is green; in the background, then END YOUR TURN — the harness resumes you on exit; report its verdict line.)
Report: the six-line report as your final text.
```

The HARD stop budgets the *first report*; one number for the whole unit is
never honoured once a reviewer asks for changes. A trap list (section 6) is appended verbatim.

### The `Agent` call

- `subagent_type: "drone"`, the brief in `prompt`, `name` set for
  addressability (`d<n>`), **`model` mandatory and equal to the ledger's
  tier** — an omitted `model` inherits yours.
- No `isolation` parameter.
- **One wave per message**: every `Agent` call for the wave in one message.
  Act on each completion as it arrives; never batch reports.
- A drone that idles on its prompt gets one `SendMessage` nudge; the
  fallback shape is a file-pointer brief. Log the idle: `mise run ledger --
  note <n> 'idled on prompt, nudged'`.

### A split shares one brief file

When you split one issue across drones, write one
`docs/handoffs/swarm-brief-<n>.md` (gitignored): the common part first, one
short section per drone. Each drone's `prompt` is the file path plus its
section name. The file's first line says whether the issue is still the
spec (a split of a `Ready` issue: it is — the drone views it as usual) or
the brief replaces it (the planner shape of section 4).

## 9. Collect

**Read reports, not diffs.** On each report, one Bash call:

```
mise run ledger -- report <n> --branch <slug> [--plan] [--stuck] [--pull]
git -C <repo> diff --stat master...<slug>
```

- `--stat` checks the fence on every unit. Open the full diff only where
  the cross-unit overview is what you are checking — a shared seam,
  anything a player would notice; the drone's done-call (or Sage) reviewed
  the rest.
- `COST:` is the drone's own count: use it to judge resume vs retire and to
  tier the next brief without waiting for `agent-cost`.
- One `advisor` call per wave for the judgement, not per unit.

**Per report: fence, content, tests — then branch.** Pick one:

1. **Land it** (section 10).
2. **Fix a one-liner yourself** in the worktree, then land.
3. **Resume the drone** with a sharp diagnosis — `SendMessage` to its name
   — within its review-round allowance.
4. **Pull it** — a `PULL` or a fork: `mise gh-project -- status <n>
   needs-design`, one-line comment, and what it blocks is not dispatched.
5. **Stop** — the same blocker twice with no fork: `mise gh-project --
   status <n> in-review` with a one-line comment, and serve the rest of the
   swarm.

**"Pre-existing failure" is a claim.** Check it against a real `master`
run (`mise run test:one -- <script>` in the main checkout) before landing
over it.

**Never acknowledge a finished drone.** Never infer from an idle that a drone's background command finished. Relay
reports to the owner in your own words; never paste diffs.

**A killed drone's worktree is checked before it is written off:**

```
git -C .worktrees/<slug> log --oneline master..HEAD
git -C .worktrees/<slug> status --porcelain
```

Commit what is there by explicit path as `wip(...)`; the two-minute
discriminator of section 1 (`check` + its own test file) decides done vs
rewrite.

## 10. Land

`mise run land -- <branch> [--closes <n>]` is the **only** way onto master
— serial by `flock`, rebases in the worktree, runs `check` + `test:dir` on
the touched dirs, fast-forwards, writes the `landed <sha>` ledger row
itself. `--closes` only on the final branch of a multi-unit issue.

- Run it from your own cheap context, in the foreground
  (`timeout: 600000`), never from a drone.
- Its verdict is the exit code or a `LANDED` / `✗` line. A filter on its
  output must match both: `grep -E 'LANDED|✗|ERROR'` — never success alone.
- A non-zero is handed back to the drone once with the failing line; twice
  is a stop (section 9, option 5).
- `checkout -- .` a worktree that cold-imported before rebasing; re-read
  `master` before concluding a merge misbehaved — it moves under you.
- Every landing's `cost:` rows are at `scratchpad/land/land-<n>.log`; the
  ledger's cost cells are a `cat`/`grep` away, not a re-derivation.

## 11. Gate the train once

After every branch of the batch is fast-forwarded:

- **Runtime-observable batch** (`.gd` / `.tscn` changed): `mise run test`
  once, in the background, then end the turn. Red train → bisect by `mise
  run test:dir` on the merge points.
- **Scripts-only batch**: `mise run check`.
- **Docs only**: nothing.
- **After a new `class_name` landed, compare script counts** between this
  suite run and the last green one — a missing or unstaged `.uid` is a test
  that silently never ran. No hand `refresh`: `mise run test*` refreshes
  the cache itself on `class_name` drift.

## 12. Sweep, then push

Before the gate closes, sweep every `poison:` line and `NOTES:` follow-up
from the reports. **The board is the last resort, not the first:**

1. **One-liners** — apply yourself in the main checkout as one docs
   commit.
2. **Bounded and mechanical** — a doc row, a rename, a prune, a missing
   twin test, a stale comment, a `.tres` that should exist: no design
   question, a drone-unit or less — goes to **one sweep drone appended to
   the train**, on the same branch discipline as any unit.
3. **A genuine fork, an owner call, or work past a drone-unit** earns an
   issue, filed through the `spec` skill; it stays in `Intake` for the
   owner, a fork written as a menu. Never a "follow-ups from swarm"
   grab-bag: each line in one is a unit you declined to dispatch.

Then:

```
git -C <repo> push origin master
mise gh-project -- hygiene --fix
```

`Closes` fires on push; `hygiene --fix` derives every hub. A blocked unit
goes back to `ready` with a comment — never `in-progress` with nobody on
it.

## 13. Tear down

Only a drone that has reported and will not be resumed:

```
mise run worktree:rm -- <slug>
git -C <repo> branch -d <slug>
```

Never `-D` until you know why `-d` refused.

## Stop and relief

- **A stop from the owner outranks everything, including spawning.** Go
  quiet: no dispatch, no merge, no test, no review. If a relief session has
  named itself, you owe it exactly one wake per in-flight drone: on each
  report, `mise run ledger -- report <n> --branch <slug>` and `SendMessage`
  relief one line. Never redirect a drone to relief's address — its report
  reaches you regardless, and your wake is the relay.
- **Relief at 50k below the ceiling** (section 3): say so to the owner in
  one line, dispatch nothing more, land what arrives, and leave the ledger
  current — `/relief` adopts it.

## Close the run

1. `mise run agent-cost` — fill the ledger's `adv` / ctx / calls / priced
   cells from it (`--main` prices your own session).
2. `mise run ledger -- close` — archives the ledger.
3. **End with the session report** (`docs/domain/session-report.md`): one
   row per unit under `Landed`; the sweep of section 12 rendered as
   `Follow-ups` with a disposition each — *fixed now* or *a drone did it*
   before *filed*; `Not done` never silent; `Needs the owner` for open
   calls.

Learned something the skill does not say? `mise run feedback -- post swarm
<kind> <file>`.

## Train mode

When the launch prompt says *train mode, train `<t>`*, you are a
`swarm-lead` subagent whose parent is the train's **top session**, not a
person. Every section above holds; these lines replace their counterparts.

**Ledger**

- Your prompt names your swarm ledger,
  `docs/handoffs/swarm-<date>-<lead-name>.md`. Every tree lead shares the
  top's session id, so the ledger tool's session lookup is never consulted:
  export it on **every** `ledger` and `land` call —
  `SWARM_LEDGER=<path> mise run ledger -- …`,
  `SWARM_LEDGER=<path> mise run land -- …`. A bare call lands in whichever
  lead's file is newest.
- Nothing is `adopt`ed. A relief prompt names the dead outgoing's file to
  read and your own to write; the whip ledger path in the prompt is read,
  never adopted.
- A row before dispatch is the claim: a unit with a row in any other live
  ledger — a draining lead's included — is never dispatched.
- `SWARM_LEDGER=<path> mise run ledger -- close` at train end.

**Roles**

- No Sage: drones' advisor is the `advisor` tool, and every brief says so.
- No whip verbs, no relay: the top carries the transport. You report by
  **returning** the session report as your final text.

**Dispatch — background drones**

- Still one wave per message, every `Agent` call now
  `run_in_background: true`. Dispatch is the one background thing in the
  tree.
- Make the inbox before the wave: `mkdir -p <inbox>/done`, where `<inbox>`
  is `docs/handoffs/swarm-<date>-<lead-name>.inbox/` (absolute path).
- Every brief's suite policy is the foreground one (`never the full suite`,
  or `in the foreground, timeout 600000` where allowed) — a backgrounded
  command ends a subagent's turn early and its report never comes.
- Every brief ends with the three-act final act, in order, replacing the
  `Report:` line:

```
Final act, in this order: (1) write your six-line report to
<inbox>/<unit>.md (absolute path given), (2) SendMessage("<lead-name>",
<the same report>), (3) the same report as your final text.
```

**Collect — the foreground inbox nap**

- A background child's ordinary report never reaches you by itself; its
  `SendMessage` does. So with any row in flight you never end your turn:
  nap in the foreground on the inbox,

```
until [ -n "$(find <inbox> -maxdepth 1 -name '*.md' -print -quit)" ]; do sleep 20; done
```

  with `timeout: 600000`. This is the one sanctioned sleep loop.
- On **every** return — a file or the ten-minute cap — read the inbox:
  handle each report (section 9, then land in the foreground), then move
  the file to `<inbox>/done/`. A second wake for a unit already handled is
  nothing: nap again.
- On a cap return with no file, check your drones by `ListAgents`. A drone
  shown `completed` or `killed` with no report file ended without its final
  act and is silent: treat it as a failed unit yourself — check its worktree
  (section 9, the killed-drone check), `mise run ledger -- note <n>
  'ended without report'`, then re-dispatch or retire the unit per section
  9. The top's stall tick is only the second net.
- A wake whose body is not the six-line report gets one `SendMessage` to
  continue — never a transcript poll, never a `pgrep` wait.
- Gate suite and `land` run in the foreground (`timeout: 600000`), never
  backgrounded.
- End the turn only when no row is in flight. A lead that slipped out of
  its nap with rows in flight ends on the one line
  `interim: <n>/<m> landed, <k> in flight` — nothing else.

**Stop and relief**

- The owner's stop arrives as a message from the top; it drains when your
  nap returns, ten minutes at most. Then section *Stop and relief* as
  written.
- **The relief threshold is your own context** — the ceiling of section 3,
  relief 50k below it — never the train's size. What train mode changes is
  the moment: the notice itself, not the next boundary. On the notice,
  `SendMessage` the top one line — `relief now; I keep <unit list>` — then
  dispatch nothing more, land each report as it arrives, close the ledger
  and return your report. Never spawn the relief yourself; the top launches
  it.
- As a relief lead: dispatch beside the draining lead up to the cap minus
  its `dispatched` rows; when only units blocked on it remain, end your turn
  on `blocked on <outgoing>` until the top's `drained` line wakes you.

**Close**

- `SWARM_LEDGER=<path> mise run ledger -- close`, then the session report
  as your final text — the return is the report. No `interim:` line on a
  clean end.
