# Swarm — charter

The design behind `.claude/skills/swarm/SKILL.md`. The skill is derived from
this; change the wish here, then re-derive the file. See
[README](README.md) for the protocol. Sibling charters: [drone](drone.md)
(the leaf), [swarmify](swarmify.md) (the gate that feeds this).

## What swarm is for

Swarm is the **orchestration** skill: one session holds the DAG of `Ready`
issues, dispatches each unit to a `drone` in its own worktree, reviews what
comes back, lands it, gates the train, pushes. `relay` is this at wave size 1
and `relief` is the fresh session that takes a swarm over — both keep their
own skills and point here for the laws. The skill is a Claude Code skill;
the opencode column it once carried described a harness this repo has no
config for and is gone.

The three things the orchestrator alone can do — and the only things it
should spend its context on — are: **hold the DAG**, **gate the train**,
**decide** (tier, fence, merge/resume/abandon). Reading, grepping, typing and
verifying are all delegated downward.

## The cost model

Two contexts compound. The **lead's**: every downstream turn (review, land,
next dispatch, reply) re-sends a context that has kept growing, so the last
5% of a swarm costs more than the first 50% and low-at-launch is what buys
the room to land the last unit. The **drones'**: covered by the drone
charter — the lever there is the integral Σ(context × turns), and the
biggest input to it is how much orientation the *issue* already carries,
which is swarmify's job, not the brief's.

The lead's cost per unit is a count of **wakes** — every drone stop wakes
its spawner whatever it wrote — times the context at each wake. With the
lead reviewing and landing, a clean unit is **two wakes** (the report, the
land). That is the shape chosen here, over the one that made a persistent
Fable land: the mechanical step is not where a Fable earns its seat, and its
context compounded across every drone's questions. The drone-side
arithmetic decides the advisor cap: one `advisor` call at context *c*
costs ≈ 5*c* sonnet units; Sage costs ≈ 20–25k Fable per unit ≈ 100–125k
sonnet units, mostly cache reads. So `advisor` beats Sage only at one
call made before ~100k — which is exactly the loop-breaking use the
owner wants, and why the drone's second call is a retirement.

Everything is measured after the fact by `mise run agent-cost` (`priced`
column, sonnet units) and logged per unit in the ledger; the tier heuristic
and the per-unit budget are tuned from those rows, never from memory. The
rows so far say the tier default is opus, not sonnet: on medium units a
Sonnet drone integrates 3–4× the context (Σctx) of an Opus drone doing
comparable work, in 2–3× the calls, and lands at the same or higher
`priced` — the per-call discount is eaten by call count. Sonnet wins only
on small units with an existing named test.

## Laws

**Gate**

1. **Pre-decided, decomposable, mechanical, unattended, affordable.** Every
   design question is answered on the issue (it is `Ready`, or it is not
   swarmed); the work comes apart into units a drone can hold; a failing
   test or exact spec defines done; nobody needs the owner mid-flight; the
   budget (law 6) fits. Any failure → `warp` the single highest-value issue
   instead.
2. **A unit that builds a new surface — a file its acceptance needs that does
   not exist — is a whole-issue unit, opus-tier, reviewed like a feature.**
   A draft that exists but was never run is *not* that: `mise run check` plus
   its own test file, two minutes, settles which.
3. **Three or more deliverables in one unit is a split**, done before
   dispatch, never left to a drone.

**Sizing and the lead's budget**

4. **Workers: 2–5, never ten.** Prefer landing four issues to starting
   twelve. Cluster by shared context first (one drone, several units, hot
   context), partition by file second; fewer drones wins.
5. **Per-unit cost is the ledger's number.** Ask the owner for the remaining
   window as one figure; price the wave from the last run's `agent-cost`
   `priced` per landed unit, tier-adjusted. No fixed percentage.
6. **Dispatch ceiling = ceiling(model) − 15k × drones in flight**, on the
   hook's `CONTEXT SIZE` marker: 250k for a Sonnet lead, 200k for an Opus
   lead; each in-flight drone reserves ~15k of settling turns (report,
   review, land — three turns, not ten). Past the ceiling, dispatch nothing
   new. **Request relief 50k below it.** Duplicate dispatch — a drone
   replying "already done" — overrides every number: the lead is past its
   useful context now.
7. **A stop from the owner outranks everything, including spawning.** The
   response is: redirect every in-flight drone to report to relief's actual
   address, then go quiet — no dispatch, no merge, no test, no review.

**Roles**

8. **The drone's advisor is the `advisor` tool**, named in the brief, and the
   brief says *when*: early — on the first loop (three failed cycles), on a
   design doubt, on a stub that looks wrong — never on a green path, and
   **once, before ~100k**: a call costs ~5× the drone's context in sonnet
   units (a Sonnet drone at 80k → ~400k, about one whole unit; at two calls
   it is already Sage-priced), so a second call means retire. Its job is
   calm in one message: the straight route, or "retire, this needs another
   design pass". `agent-cost` prices each advisor call and adds it to
   `priced`, so the Sage-vs-advisor comparison is on one axis.
9. **The lead reviews and lands.** `--stat` for the fence on every unit;
   the full diff on opus-tier and anything a player would notice; one
   `advisor` call per wave for the judgement, not per unit; `mise run land`
   from the lead's own cheap context. Never resume a deep-context drone to
   rebase, merge or land.
10. **Sage is opt-in, and never lands.** At four or more concurrent drones,
    or an absent owner, spawn one as reviewer and advisor; drones then ask
    Sage instead of `advisor`. **`approved` goes back to the drone**, which
    carries it in its report (`NOTES: Sage approved, 2 exchanges`), and the
    lead lands off that report — N wakes, unchanged. Sage messages the lead
    only for exceptions (a second failed land, a cross-unit conflict, a
    mis-tier) and one `REVIEWED:` list at the end. Sage runs nothing that
    mutates the repo.
11. **The planner fork is a fallback, not a shape.** A `Ready` issue already
    carries its reading list, seam map and stubs; a Sonnet lead can dispatch
    from it directly. A throwaway Opus planner subagent is for the run where
    the issues are not that well specced — then it writes the DAG and briefs
    and dies, and the fix for next time is a better swarmify pass.

**Dispatch**

12. **The brief is bare.** Issue number(s) and hub; owned paths (the fence,
    *including* scenes and boards that reference the changed system); seams
    this run (who owns what, the seam's sha); tier; "your advisor is the
    `advisor` tool" (or Sage); a turn/time budget as a HARD stop that
    budgets the *first report* ("do not take call N+1"), with a small fixed
    allowance per review round and a two-round cap — one number for the
    whole unit is never honoured once a reviewer asks for changes, and no
    drone counts its own calls anyway; "commit early and often, even
    partial" as its own
    line; the three suite clauses if a full suite is allowed at all, else
    "never the full suite". Nothing the issue already says.
13. **Brief in `prompt`; `name` for addressability; `subagent_type: "drone"`;
    `model` mandatory and equal to the ledger's tier.** No `isolation`
    parameter — the drone makes its own `mise` worktree. If a drone idles on
    its prompt, one `SendMessage` nudge, then the file-pointer brief is the
    fallback shape; log the idle in the ledger.
14. **Before every dispatch, in one Bash call: the ledger, the kanban claim,
    and `mise run issue-drift -- <n>`.** The ledger (`docs/handoffs/
    swarm-<date>.md`, gitignored, rewritten in place, ≤1.5k tokens) is the
    at-most-once record and the relief briefing; `mise gh-project -- status
    <n> in-progress` claims the issue; `issue-drift` is silent when the
    issue's stamped reading list still holds, prints the drifted entries
    otherwise (then one `Explore(model: haiku)` re-verifies them before the
    brief is written), and says `no stamp` on a pre-charter issue.
15. **Shared contracts land on master first.** A seam every unit overrides,
    a registry every unit appends to, a `.tres` every unit touches — the
    lead commits it before spawning; drones branch from the tip.
16. **One wave per message.** All `Agent` calls for a wave in one message;
    act on each completion as it arrives, never batch reports.

**Collect and land**

17. **Read reports, not diffs.** A report is five lines; a wall of text is a
    drone-contract violation, not something to summarise.
18. **Per report: fence, content, tests — then branch.** Land it; fix a
    one-liner yourself then land; resume the drone with a sharp diagnosis;
    or stop — `in-review` with a one-line comment naming the fork — and
    serve the rest of the swarm.
19. **"Pre-existing failure" is a claim.** Check against a real `master` run
    before landing over it.
20. **`mise run land -- <branch> [--closes <n>]` is the only way onto
    master.** Serial by `flock`; rebases in the worktree; `check` +
    `test:dir`; `--closes` only on the final branch of a multi-unit issue.
    A non-zero is handed back to the drone once; twice is a stop.
21. **The full suite runs once per train**, after every branch of the batch
    is fast-forwarded, and only when the batch is runtime-observable
    (`.gd`/`.tscn` changed) — `check` for a scripts-only batch, nothing for
    docs. Red train → bisect by `test:dir` on merge points.
22. **After a new `class_name` lands, `mise run refresh` on master, and
    compare script counts** — a missing or unstaged `.uid` is a test that
    silently never ran.
23. **`Closes` fires on push.** Then `mise gh-project -- hygiene --fix` once,
    which derives every hub. A blocked unit goes back to `ready` with a
    comment; never `in-progress` with nobody on it.
24. **A killed drone's worktree is checked before it is written off**: `git
    -C .worktrees/<slug> log master..HEAD` + `status --porcelain`; commit
    what is there by explicit path as `wip(...)`; the two-minute
    discriminator of law 2 decides done vs rewrite.

**Teardown and hygiene**

25. **Tear down only a drone that has reported and will not be resumed**;
    `worktree:rm` then `branch -d` (never `-D` until you know why `-d`
    refused).
26. **Always `git -C`**, never a bare `git` after a `cd`; explicit-path
    `git add`; `checkout -- .` a worktree that cold-imported before
    rebasing; re-read `master` before concluding a merge misbehaved — it
    moves under you.
27. **Never acknowledge a finished drone**; never infer from an idle that a
    drone's background command finished; relay reports in your own words,
    never paste diffs.

## Incident corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-07-30 | field | a named teammate returned "will receive instructions via mailbox" and idled; later runs measured 5/5 and 7/7 idles on the placeholder-prompt shape, 2/2 starts on a file-pointer brief | 13 |
| 2026-08-03 | two runs | one issue ≈ 10–20% of a rate-limit window; shedding six mid-flight drones cost ~10% alone; a run that succeeded came in at ~12%/unit with the formula predicting 1.4× that | 5 |
| 2026-08-05 | settings | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` confirmed set; checking it mid-session tells you nothing actionable | 13 |
| 2026-08-26 | 5/5 workers | after the mailbox brief, each did one action (the worktree) then idled; one nudge drove whole jobs | 13 |
| 2026-08-27 | a second unit | new panel + new read path + display rule clustered as a drone's second unit ran to ~400k uncommitted and was halted; siblings cost a third | 2 |
| 2026-08-27 | #621 draft | deferred twice as unverified new surface; was substantially complete, one fixture bug — "a commit message is a claim, not evidence" | 2, 24 |
| 2026-08-27 | #627 | a drone's new test `.uid` generated but never staged; green everywhere, one script short; caught only by comparing counts | 22 |
| 2026-08-27 | stop compliance | owner "stop taking turns" at 253k; lead spawned a worker 48 s later and another at ~300k, which ran 260 turns to 319k | 7 |
| 2026-08-28 | owner | "orchestrator holds all the cards, if they merge in 10 commits… then merge all then test once" — the train; 11 suites in one night before it | 21 |
| 2026-08-28 | ledger | 20 commits of scaffolding before `swarm-*.md` was gitignored | 14 |
| 2026-09-08 | brief | two of three suite clauses present; the worker polled ~a dozen times; the lead polled its own gate ~12 times the same day | 12 |
| 2026-09-10 | spend limit | two drones killed in one minute; one had committed nothing and was saved by the lead committing its tree by hand | 12, 24 |
| 2026-09-10 | idle | a lead read a drone's idle as "the test run drained" and nudged it wrong; the godot process was alive | 27 |
| 2026-09-11 | Sage trial | 6 drones, 4 reviews, 5 real findings, one laundered owner quote caught, one 26-minute stall behind a sibling's audit; lead at ~180k reading every diff anyway | 9, 10 |
| 2026-09-13 | wave 2 | no `model` param passed; both opus-tiered units ran as sonnet | 13 |
| 2026-09-14 | postmortem | three of four Sonnet overruns were spec gaps (bundled unit, undeclared scene seams, an interaction hidden behind an adjective) — the origin of the swarmify charter; ≥3 deliverables → split; 80-call budget worded as a HARD stop; second brief of a collision pair names the first's landed sha | 3, 12 |
| 2026-09-14 | addendum | Sage cost ~20–25k Fable per landed unit plus ~30k per successor; owner: "i think Sage does consume a lot compared to `advisor` tool" | 8, 10 |
| 2026-09-15 | smoke | a haiku `drone` with `name` set started on its `prompt` — no idle, 5 calls / 32 s — and saw CLAUDE.md; the idle lore is stale for the typed drone (n=1) | 13 |
| 2026-09-15 | owner | "letting [Sage] do mechanical stuff (merging) instead of just answering implementation questions or rating implementations / acceptance also sounds like a bad idea. it's there mostly to 'be smart' … a drone failing to get a test green should better just ask 1 question instead of making 20 frantic tool calls … that's an advisor who should bring back the calm … or tell them straight: stop trying, retire" | 8, 9, 10 |
| 2026-09-16 | 9 units | Sonnet on medium units: kb 108 calls / Σctx 9.4M / 1.59M priced for 263 lines vs place (opus) 50 calls / 3.9M / 1.61M for a new system; migrate (opus) 1343 lines at 0.23M per 100 lines, the cheapest row; all three 80-call overruns were review-round loops after the first report (108/95/113) | 3, 6, 12 |
| 2026-09-16 | Sage | stalled 28 min: its background Explores' completions notified the lead, not Sage; audits run inline in Sage's own turn | 10 |
| 2026-09-17 | owner | every drone turn-end wakes the lead, so "the only way to avoid [idle wakes] is to let the drone's final turn be a back report to main … the drone is done anyway. If sage disapproves they will report back (or file a new drone), if OK consider it retired or spent" — drones no longer wait for a verdict; `APPROVED <sha>` goes to the lead, findings to the drone; a clean unit is two lead wakes (fence, land). The prior run had ~15 non-actionable lead wakes and 2–3 "waiting for Sage" drone turns per unit at peak context | 10, 13 |
| 2026-09-15 | owner | thresholds "depend on the model … and how much is in flight, if 5 drones working expect 5× the turns taken to settle each, then 150k might already be a lot" → the ceiling formula; sizing "worker cap + ledger Σctx, drop the %-window table"; "the swarm mayve mentioned an issue planner throwaway Opus but our new swarmify skill would (i hope) make that largely obsolete" | 5, 6, 11 |

## What the skill must not contain

- Any row above, any issue number, any date, the opencode column, the
  harness table, the Claude Code `<details>` block on harness worktrees
  (`isolation: "worktree"` is not used).
- The wake arithmetic, the window-percentage table, the worker-cost table.
- Restatements of the drone's standing rules (they are in the agent), of
  `warp`'s rebase discipline (`land` mechanises it), or of always-on rules.

## Open follow-ups

- **`/compact` with drones in flight** (owner, 2026-09-15): if a lead can
  compact itself and still receive its drones' completion notifications,
  `relief` shrinks to the ran-out-of-tokens case. Untested; try once,
  deliberately, with one drone in flight.
- **`advisor` caching** (owner, 2026-09-15, "[source: claude.ai docs]"):
  with remote caching on, ~3 calls per drone may be cheaper than 2 uncached.
  Verify via the `claude-api` skill before it becomes a law.
- **Idle count per dispatch** on the first sonnet/opus swarm under law 13;
  if it stays zero, drop the nudge/file-pointer fallback from the skill.
- `.claude/agents/sage.md` was patched for law 10 (reviewer only, never
  lands) and deserves its own charter; `relay` and `relief` still carry
  their own dated lore and should be re-derived from this charter too.
