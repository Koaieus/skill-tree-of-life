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

Read `.claude/agents/drone.md` once so you know what a drone already
carries; never restate it in a brief.

## Gate — do not swarm the wrong work

All five must hold, else `warp` the single highest-value issue instead:

1. **Pre-decided** — every design question is answered on the issue. It is
   `Ready`, or it is not swarmed. Never pin a fork in a brief.
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
Never hope a drone self-splits.

## Size the swarm

- **2–5 drones, never ten.** Prefer landing four issues to starting twelve.
- **Cluster by shared context first, partition by file second.** Issues that
  read the same subsystem are one drone doing several units with hot
  context; overlap *inside* a drone is free, overlap *across* drones is a
  wave boundary. Fewer drones wins.
- **Per-unit cost is the ledger's number**, not a constant: ask the owner for
  the remaining window as one figure, and price the wave from the last
  run's `mise run agent-cost` `priced` per landed unit at the tier you are
  dispatching.

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
  `Agent` call is new work. Redirect every in-flight drone to report to
  relief's *actual address* (from `ListAgents` or the owner), then go quiet:
  no dispatch, no merge, no test, no review.

## Roles

- **Drones' advisor is the `advisor` tool**, named in every brief with the
  *when*: once, early (before ~100k), on the first loop, a design doubt, or
  a stub that looks wrong — never on a green path. A second call means
  retire. The tool's job is calm in one message: the straight route, or
  "retire, this needs another design pass".
- **You review and you land.** `git diff master...<branch> --stat` for the
  fence on every unit; the full diff on opus-tier units and anything a
  player would notice. One `advisor` call per wave for the judgement, not
  per unit. `mise run land` from your own context — never resume a
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

## The cycle

### 1. Read the issues once, delegate the rest

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
   for a unit of ≤150 lines with a named test that already exists; `haiku`
   only for pure mechanical churn. Priced per landed line, opus is the
   cheaper tier on medium units — it finishes in a third of the calls and
   context — so the default is not the cheap-looking model. A Sonnet past
   three advisor/Sage exchanges is mis-tiered by definition — the ledger
   records it and the next brief is tiered from that.
4. **Shared contracts land on master first.** A seam every unit overrides,
   a registry every unit appends to, a `.tres` every unit touches: commit
   it in the main checkout, test it, then spawn — drones branch from the tip.
5. **Pre-flight envelopes against real content** when units fill a layout
   you own; delegate the measurement.

If the work will not come apart, that is a real answer: `warp`.

### 3. Dispatch — one Bash call, then one message

**Before every dispatch, in a single Bash call:**

```bash
cat docs/handoffs/swarm-<date>.md 2>/dev/null          # the ledger — at-most-once record
mise gh-project -- status <n> in-progress               # claim on the persistent board
mise run issue-drift -- <n>                             # silent = the Ready comment still holds
```

- **The ledger** (`docs/handoffs/swarm-<date>.md`, gitignored — write it,
  never commit it) is the roster table — unit / drone name / tier / state
  (`dispatched@HH:MM` → `reported` → `landed <sha>` | `rejected→redispatched`)
  plus per-unit `model / ctx at report / tool calls / advisor calls /
  findings / priced` — and the queue order. Rewrite in place on every
  dispatch, report, land and owner call; ≤ ~1.5k tokens; it is what relief
  reads. Delete it at teardown; anything that must outlive the run goes to
  the issue.
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
  ledger.

**The bare brief** — ~15 lines, only what the issue cannot know:

- **Issue number(s)**, plus the hub if there is one.
- **Owned paths** — the exact fence, *including* scenes, boards and sandbox
  panels that reference the changed system (the seam map on the issue lists
  them).
- **Seams this run** — "`#m` (drone `foo`) owns `ui/hud/`; the seam is
  `HudRoot.compose()`, on master at `<sha>`." For a collision pair, the
  second brief names the first's landed sha.
- **Tier**, and that it decides the drone's model.
- **"Your advisor is the `advisor` tool: once, early, on the first loop or a
  design doubt; a second call means retire."** (Or "Sage is your advisor;
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

Acceptance restated, "what done means", file maps, house rules by name,
`git show` tours — none of it. If the issue cannot carry it, the issue is
not `Ready`: bounce it, don't patch it in a brief.

### 4. Collect — act on each report as it lands

Read the five-line report, not the diff. A wall of text is a drone-contract
violation; do not propagate it. Clip the cost onto a command you are running
anyway (`land` prints it; `mise run agent-cost -- --branch <slug>` otherwise)
and put `priced` in the ledger row.

Per report, in order:

```bash
git diff master...<branch> --stat        # 1. fence — every tier
git diff master...<branch>               # 2. content — opus tier / player-visible only
```

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
- **Stuck** — the same blocker twice after a resume, or a real fork: move the
  issue to `in-review` with a one-line comment naming the fork, and serve
  the rest of the swarm. A blocker reported on a *first* report is the
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

**The authoritative suite runs once per train**, after every branch of the
batch is fast-forwarded — and only when the batch is runtime-observable:
`mise run test` if `.gd`/`.tscn` changed, `mise run check` for scripts-only,
nothing for a docs-only train. Red train → bisect with `test:dir` on the
merge points. Launch the suite backgrounded and end your turn.

**After a new `class_name` lands, `mise run refresh` on master and compare
script counts** before and after: a `.uid` that was never generated, or
generated but never staged, is a test that silently never ran.

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

Delete the ledger. Relay reports to the user in your own words — never paste
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
