---
name: swarm
description: Orchestrate parallel `drone` subagents over `Ready` issues — hold the DAG, dispatch one fenced unit per drone in its own worktree, review each report as it lands, land it with `mise run land`, gate the train once, push. Use when the user says "swarm #<n>" / "swarm #<n>, #<m>" or asks to parallelise pre-decided work across subagents. `relay` is this at wave size 1; `relief` takes a running swarm over.
---

# Swarm

Why each step says what it says: `docs/charters/swarm.md`.

You do three things and spend context on nothing else: **hold the DAG**,
**gate the train**, **decide** (tier, fence, merge / resume / abandon).
Reading, grepping, typing and verifying are delegated downward.

## 1. Orient — one Bash call

```
mise run ledger -- show; mise gh-project -- list; git -C <repo> worktree list; ls .claude/worktrees/
```

- `/swarm` always starts its own run: another live ledger on disk is never a
  relief trigger (`/relief` runs `ledger -- adopt`; the verb decides relief).
- **Resume read.** Any resume — a drone's wake, a bare `continue` — starts
  with `mise run ledger -- show` (train mode: `cat "$SWARM_LEDGER"`). A
  `## Draining` section present means you are draining for the rest of your
  life: spawn no drone, land each kept unit's report as it arrives, resume a
  kept unit's own drone by `SendMessage` only to finish it, and treat every
  other unit as the relief's. `continue` is never an instruction to dispatch.
- A stray worktree (`.claude/worktrees/` included) whose branch is merged or
  holds nothing worth mining is deleted now, never carried as an owner
  question: `git -C <path> log master..HEAD` + `status --porcelain`, then
  `mise run worktree:rm -- <slug>` and `git branch -d <slug>`.
- Read each issue once: `gh issue view <n> --comments`.

## 2. Gate the run

1. **Pre-decided, decomposable, mechanical, unattended, affordable.** Every
   design question is answered on the issue (it is `Ready`, or it is not
   swarmed); the work comes apart into units a drone can hold; a failing test
   or exact spec defines done; nobody needs the owner mid-flight; the budget
   (step 3) fits. Any failure → `warp` the single highest-value issue instead.
2. **A unit that builds a new surface** — a file its acceptance needs that
   does not exist — is a whole-issue unit, opus-tier, reviewed like a feature.
   A draft that exists but was never run is not that: `mise run check` plus
   its own test file, two minutes, settles which.
3. **Three or more deliverables in one unit is a split**, done before
   dispatch, never left to a drone. Size net at dispatch: a unit expected to
   exceed ~40 calls or ~120k context is split before dispatch.

## 3. Size the wave and your own budget

4. **Workers: 2–5, never ten.** Prefer landing four issues to starting
   twelve. Cluster by shared context first (one drone, several units, hot
   context), partition by file second; fewer drones wins.
5. **Per-unit cost is the ledger's number.** Ask the owner for the remaining
   window as one figure; price the wave from the last run's `mise run
   agent-cost` `priced` column per landed unit, tier-adjusted. No fixed
   percentage. Tier default is opus; sonnet only for a small unit with an
   existing named test or mechanical churn where rigor buys nothing.
6. **Dispatch until your own context passes 150k, then nothing new.** The
   trigger is the hook's first `CONTEXT SIZE SO FAR` notice — one number for
   every lead model, no per-drone deduction, no margin below it. At the
   notice: write the `## Draining` section (step 34), send the relief request
   (standalone: one line to the owner, `relief needed; I keep <unit list>`;
   train mode: `SendMessage` to `main`, `relief now; I keep <unit list>`),
   dispatch nothing new, and drain — review and land each report as it
   arrives. A drone replying "already done" to a duplicate dispatch overrides
   the number: you are past your useful context now.
7. **A stop from the owner outranks everything, including spawning.** Go
   quiet — no dispatch, no merge, no test, no review. If a relief session has
   named itself, owe it exactly one wake per in-flight drone: on each report,
   update that drone's ledger row and `SendMessage` relief one line. Never
   redirect a drone to relief's address.

## 4. Roles

8. **The drone's advisor is the `advisor` tool**, named in the brief with
   three moments: **Plan** (after orientation, before the first edit),
   **Stuck** (at most once — a state: it can no longer say what it believes
   is wrong and what the next attempt will show; a typo or wrong path is not
   stuck), **Done** (only when no Sage runs: the advisor reviews the diff
   instead of you reading it). Its answer is one message: the straight route,
   or "stop — report `PULL`" on an unresolved fork or a wall. A `PULL` takes
   the unit off the run and back to `Needs design`, and what it blocks is not
   dispatched. The done-call checks the unit; you still check what spans
   units. A Sonnet that spent its stuck call, or `PULL`ed on something that
   was not a fork, is logged as a mis-tier.
9. **You review and land.** `git -C .worktrees/<slug> diff --stat
   master..HEAD` for the fence on every unit; the full diff only where the
   cross-unit overview is what is checked (a shared seam, anything a player
   would notice); one `advisor` call per wave for the judgement, not per
   unit; `mise run land` from your own cheap context. Never resume a
   deep-context drone to rebase, merge or land.
10. **Sage is opt-in, and never lands.** At four or more concurrent drones,
    or an absent owner, spawn one `sage` agent as reviewer and advisor —
    `Agent` with `subagent_type: "sage"`, `name: "Sage"`; its standing brief
    is the agent file, the prompt names the swarm ledger and the units in
    flight. Drones then ask Sage instead of `advisor` and the brief line becomes
    "Sage is your advisor (SendMessage to Sage)". `approved` goes back to the
    drone, which carries it in its report (`NOTES: Sage approved, 2
    exchanges`); you land off that report. Sage messages you only for
    exceptions (a second failed land, a cross-unit conflict, a mis-tier) and
    one `REVIEWED:` list at the end. Sage runs nothing that mutates the repo.
    Train mode: no Sage.
11. **The planner fork is a fallback, not a shape.** A `Ready` issue carries
    its reading list, seam map and stubs; dispatch from it directly. Only
    when the issues are not that well specced, a throwaway Opus planner
    subagent writes the DAG and briefs and dies.

## 5. Dispatch

15. **Shared contracts land on master first.** A seam every unit overrides,
    a registry every unit appends to, a `.tres` every unit touches — commit
    it before spawning; drones branch from the tip.
29. **A genuinely hard unit gets a trap list before its drone starts.** For
    a bit-exact transliteration, a solver port, anything a green suite would
    not catch: ask an idle peer session (`ListAgents`) for *where this will
    break* — not a plan, not a file summary — and (1) which files it holds so
    the drone stays clear; say "if you're mid-task, answer (1) alone".
    Dispatch without waiting; relay the list verbatim into the brief when it
    arrives, anything flagged *unverified* as an open question to resolve by
    reading, never as fact.
14. **Before every dispatch, in one Bash call: the draining guard, the
    ledger row, the kanban claim, and the drift check.**

    ```
    # train mode: export SWARM_LEDGER=<path from the launch prompt> first, on this and every ledger/land call
    { [ -n "${SWARM_LEDGER:-}" ] && grep -q '^## Draining' "$SWARM_LEDGER" \
      || mise run ledger -- show | grep -q '^## Draining'; } && echo DRAINING && exit 0
    mise run ledger -- dispatch <n> <drone> <tier>
    mise gh-project -- status <n> in-progress
    mise run issue-drift -- <n>
    ```

    `DRAINING` → no dispatch. `ledger -- dispatch` creates the file for a
    new run and prints the roster back (the read is free); the roster is
    written by commands, never by you remembering. `issue-drift` is silent
    when the stamped reading list still holds, prints the drifted entries
    otherwise (then one `Explore(model: haiku)` re-verifies them before the
    brief is written), and says `no stamp` on a pre-charter issue. The
    ledger (`docs/handoffs/swarm-<date>-<HHMM>.md`, gitignored, ≤1.5k
    tokens) is the at-most-once record and the relief briefing; read it only
    with `mise run ledger -- show`, never a path built from a date; `ledger -- note <n> '…'` appends to a row's notes (an idle, a
    poison line) without touching its state. A unit with a row in another
    live ledger — a draining lead's included — is never dispatched.
12. **The brief is bare.** Nothing the issue already says, nothing the drone
    already carries. Never open `.claude/agents/drone.md`; what a drone
    carries is this: it makes its own worktree (`mise run worktree:new --
    <slug>`) before any edit, so no `isolation` parameter; reads the issue
    once, writes only owned paths, reads anything; `git add`s by explicit
    path, never stashes, never lands, never writes `Closes #n`; writes a
    named test RED first and confirms it ran, and authors no test for an
    exact-spec / visual / tuning unit; holds "pre-existing failure" as a
    claim and notes it; has a coherent commit by ~150k, retires on a blown
    budget with a successor brief on the issue, never finishes past the stop;
    calls the `advisor` tool only when the brief names it, never the user;
    defaults an open number as a knob, not a doubt; batches shell commands,
    never polls or idles, verifies on the ladder `check` → `test:one` →
    `test:dir`; ends its turn with its report as its final text — spent once
    it has reported. The template, verbatim:

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

    The second brief of a collision pair names the first's landed sha.
    Train mode appends the three final acts of step 10 after it.
33. **A split shares one brief file.** When you split one issue across
    drones, write one `docs/handoffs/swarm-brief-<n>.md` (gitignored) with
    the common part first and one short section per drone; each drone's
    `prompt` is the file path plus its section name, and the file's first
    line says whether the issue is still the spec (a split of a `Ready`
    issue: it is — the drone views it as usual) or the brief replaces it
    (the planner shape of step 11).
13. **The `Agent` call:** brief in `prompt`; `name` for addressability;
    `subagent_type: "drone"`; `model` mandatory and equal to the ledger's
    tier. No `isolation` parameter. If a drone idles on its prompt, one
    `SendMessage` nudge, then the file-pointer brief is the fallback shape;
    log the idle with `ledger -- note`.
16. **One wave per message.** All `Agent` calls for a wave in one message;
    act on each completion as it arrives, never batch reports.

## 6. Collect and land — per report, as it arrives

17. **Read reports, not diffs.** A report is six lines:
    `BRANCH: <slug>` · `FILES: <paths touched>` · `TESTS: <what ran, what is
    green>` · `DID: <one line>` · `COST: ctx <k>, calls <n>, exchanges <n>` ·
    `NOTES: <follow-ups, poison: lines, Sage approved N exchanges, PULL>`.
    A `PULL` or a stuck stop rides in `NOTES:`. `COST:` is the drone's own count — use it to judge resume vs retire and
    to tier the next brief. A wall of text is a drone-contract violation, not
    something to summarise. Record it:
    `mise run ledger -- report <n> --branch <slug> [--plan] [--stuck] [--pull]`.
18. **Fence, content, tests — then branch.** Land it; fix a one-liner
    yourself then land; resume the drone with a sharp diagnosis; pull it — a
    `PULL` or a fork, `mise gh-project -- status <n> needs-design`; or stop —
    the same blocker twice with no fork, `mise gh-project -- status <n>
    in-review` with a one-line comment (`gh issue comment <n> --body-file
    <file>`) — and serve the rest of the swarm.
19. **"Pre-existing failure" is a claim.** Check against a real `master` run
    (`mise run test:one -- <script>` in the main checkout) before landing
    over it.
20. **`mise run land -- <branch> [--closes <n>]` is the only way onto
    master.** Serial by `flock`; rebases in the worktree; `check` +
    `test:dir`; writes the `landed <sha>` ledger row itself; `--closes` only
    on the final branch of a multi-unit issue. A non-zero is handed back to
    the drone once; twice is a stop. Its verdict is the exit code or a
    `LANDED` / `✗` line — a filter on its output must match both
    (`grep -E 'LANDED|✗|ERROR'`), never success alone.
24. **A killed drone's worktree is checked before it is written off:**
    `git -C .worktrees/<slug> log master..HEAD` + `status --porcelain`;
    commit what is there by explicit path as `wip(...)`; the two-minute
    discriminator of step 2 decides done vs rewrite. A drone that ended
    without its report: `mise run ledger -- note <n> 'ended without report'`,
    then re-dispatch or retire.
27. **Never acknowledge a finished drone**; never infer from an idle that a
    drone's background command finished; relay reports in your own words,
    never paste diffs.

## 7. Follow-ups, before the gate

28. **Sweep `poison:` lines and `NOTES:` follow-ups; the board is the last
    resort.** One-liners you apply yourself in the main checkout as one docs
    commit. Anything bounded and mechanical — a doc row, a rename, a prune, a
    missing twin test, a stale comment, a `.tres` that should exist — goes to
    ONE sweep drone appended to the train, on the same branch discipline as
    any unit. Only a genuine fork, an owner call, or work past a drone-unit
    earns an issue, filed through the `spec` skill (it stays in `Intake`, its
    fork written as a menu). Never a "follow-ups from swarm" grab-bag issue.

## 8. Gate the train and push

21. **The full suite runs once per train**, after every branch of the batch
    is fast-forwarded, and only when the batch is runtime-observable
    (`.gd`/`.tscn` changed): `mise run test` with `run_in_background: true`,
    then end the turn (train mode: foreground, `timeout: 600000`). `mise run
    check` for a scripts-only batch, nothing for docs. Red train → bisect by
    `test:dir` on merge points.
22. **After a new `class_name` lands, compare script counts** across the
    train's suite run — a missing or unstaged `.uid` is a test that silently
    never ran. No hand `refresh`: `mise run test*` refreshes the cache itself
    on `class_name` drift.
23. **`Closes` fires on push:** `git -C <repo> push origin master`. Then
    `mise gh-project -- hygiene --fix` once. A blocked unit goes back to
    `ready` with a comment; never `in-progress` with nobody on it.

## 9. Teardown and the session report

25. **Tear down only a drone that has reported and will not be resumed:**
    `mise run worktree:rm -- <slug>` then `git branch -d <slug>` (never `-D`
    until you know why `-d` refused).
26. **Always `git -C`**, never a bare `git` after a `cd`; explicit-path `git
    add`; `checkout -- .` a worktree that cold-imported before rebasing;
    re-read `master` before concluding a merge misbehaved — it moves under
    you.
35. **Sweep your run's worktrees before the final report.** `mise run
    worktree:ls`, then per worktree `git -C <path> log master..HEAD` +
    `status --porcelain`. **Your own** — a branch one of your drones
    reported, or a `.claude/worktrees/agent-<id>` whose id is one of your
    subagents' — landed or merged → `worktree:rm` then `branch -d`; dropped
    or killed → kept only if something in it is worth mining (committed
    `wip(...)`, named in the report), else removed. **Anything else** with
    nothing ahead of `master` and a clean tree is removed too, but only by a
    lead with no other lead live (the last lead of a train, or a standalone
    swarm) — a fresh drone of a live relief or sibling looks exactly like
    that. A draining lead sweeps at its own final report, not at the relief
    request. The report's `Not done` counts every worktree left, one line
    each with why.
30. **End with the session report** (`docs/domain/session-report.md`).
    First fill the ledger's `adv` / ctx / calls / priced from `mise run
    agent-cost` (your own session via `--main`; every landing's `cost:` rows
    are at `scratchpad/land/land-<n>.log`), then `mise run ledger -- close`,
    then the report: one row per unit under `Landed`; the step-28 sweep
    rendered as `Follow-ups` with a disposition each — *fixed now* or *a
    drone did it* before *filed*; `Not done` per step 35. A lesson this
    skill does not say is posted where it is learned: write it to a file,
    then `mise run feedback -- post swarm <kind> <file>`.

## 10. Train mode

32. When the launch prompt says *train mode, train `<t>`*, you are a
    `swarm-lead` subagent whose parent is the train's top session, and these
    change; every other step holds.
    - **Ledger.** The prompt names your swarm ledger
      (`docs/handoffs/swarm-<date>-<lead-name>.md`); export it as
      `SWARM_LEDGER` on **every** `ledger` and `land` call. A relief's prompt
      names the dead outgoing's file to read and the relief's own to write;
      nothing is `adopt`ed, and the whip ledger path in the prompt is read,
      never adopted. A row before dispatch is the claim; a unit with a row in
      another live ledger is never dispatched.
    - **Inbox.** Before the wave: `mkdir -p <inbox>/done` with the absolute
      path `docs/handoffs/swarm-<date>-<lead-name>.inbox/`.
    - **Dispatch** goes out in the background — one message, every `Agent`
      call `run_in_background: true` — and every brief's final act is three
      things in order: the six-line report written to `<inbox>/<unit>.md`
      (named absolute in the brief), `SendMessage(<lead-name>, <the same
      report>)`, then the report as text. A second wake for a unit already
      handled is nothing.
    - **Suite policy** in every brief is the foreground one: the middle
      clause becomes "in the foreground, timeout 600000". Nothing in the tree
      backgrounds a command; dispatch is the one background thing. Run the
      gate suite and `land` in the foreground (`timeout` 600000).
    - **Waiting.** With drones in flight never end your turn; nap in the
      foreground on the inbox,
      `until [ -n "$(find <inbox> -maxdepth 1 -name '*.md' -print -quit)" ]; do sleep 20; done`
      with `timeout: 600000`; read the inbox on every return (file or cap),
      move a handled file to `<inbox>/done/`, and on a cap return with no
      file check your drones by `ListAgents`. A wake whose body is not the
      six-line report gets one `SendMessage` to continue, never a transcript
      poll or `pgrep` wait. A drone shown `completed` or `killed` with no
      inbox file is a failed unit: step 24. Only a lead that slipped out of
      its nap ends on the one line `interim: <n>/<m> landed, <k> in flight`.
    - **Relief.** The threshold is your own 150k context, never the train's
      size. At the notice: `## Draining` section (step 34), `SendMessage` to
      `main`: `relief now; I keep <unit list>`, then dispatch nothing more,
      land each report as it arrives, close the ledger, return your report.
      Never spawn the relief yourself: the top launches it. A relief
      dispatches beside the draining lead up to the cap minus the outgoing's
      `dispatched` rows; when only blocked units remain it ends its turn on
      `blocked on <outgoing>` until the top's `drained` line wakes it.
    - **Sage is out**; drones' advisor is the `advisor` tool.
    - The owner's stop arrives as a message from the top and drains when
      your nap returns, ten minutes at most.
    - **Report** by returning the session report as your final text, after
      `mise run ledger -- close`.
34. **A draining lead knows it is draining, across any resume.** Before
    sending the relief request, write a `## Draining` section into your own
    swarm ledger's prose — `relief asked <HH:MM>; I keep <unit list>` — so
    the state is on disk before the message that makes it true. From then on
    the pre-dispatch guard (step 14) and the resume read (step 1) say so.

31. Retired; the number is kept so the laws still diff. Train mode is the
    only unattended mode.
