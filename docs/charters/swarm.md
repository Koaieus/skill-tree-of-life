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
sonnet units, mostly cache reads. So `advisor` beats Sage on price only
at small context — the plan call, which is why it is the default. The
done-call (no Sage) is dearer in tokens than the lead reading a diff; what
it buys is the lead's context, the run's scarce resource: every page the
lead reads is re-read at every later wake and brings its ceiling closer.

Everything is measured after the fact by `mise run agent-cost` (`priced`
column, sonnet units) and logged per unit in the ledger — the lead's own
session included, via `--main` (2026-09-30: a swarm lead and a concurrent
main session each blamed the other for the window; the subagents alone
measured 18.1M priced against a main session's ~1–3M, and until `--main`
existed only one side could be measured); the tier heuristic
and the per-unit budget are tuned from those rows, never from memory. The
rows so far say the tier default is opus, not sonnet: on medium units a
Sonnet drone integrates 3–4× the context (Σctx) of an Opus drone doing
comparable work, in 2–3× the calls, and lands at the same or higher
`priced` — the per-call discount is eaten by call count. Sonnet wins only
on **small or dumb units** — a small unit with an existing named test, or
mechanical churn where rigor buys nothing (owner, 2026-09-30: "Opus is more
rigorous, more effective, but loses at dumb mechanical churn").

A rate-limit-window percentage is a **snapshot unit**, never a comparable
one: the window's size moves with Anthropic's promotions ("more Claude Code
limits during …"), so an identical token cost reads as a different % on a
different week. The corpus keeps its dated %-rows as history only. The
comparable unit is `mise run agent-cost`'s `priced` column (sonnet units)
logged per landed unit in the ledger — every landing's `cost:` rows are on
disk at `scratchpad/land/land-<n>.log` (#920), so filling the ledger is a
`cat`/`grep` away, not a re-derivation.

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
   dispatch, never left to a drone. Sizing is swarmify's job (owner,
   2026-09-30: "load balancing sounds like a swarmify job indeed" — its law
   27 sizes every child before `Ready`); the lead keeps a **size net** at
   dispatch: a unit expected to exceed ~40 calls or ~120k context is split
   before dispatch. The net's numbers are the 09-30 lead's proposal adopted
   as a tentative default, not an owner call: ~40 expected calls is half the
   80-call hard stop of law 12 and ~120k leaves room under the ~150k that
   swarmify's law 27 sizes a child to finish in; a unit that already
   *looks* like it needs the whole budget will blow it.

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
   response is to go quiet — no dispatch, no merge, no test, no review —
   and, if a relief session has named itself, to owe it exactly one wake
   per in-flight drone: on each report, update that drone's ledger row and
   `SendMessage` relief one line. Drones are never redirected to relief's
   address: their reports reach the outgoing regardless, so its wake is the
   relay and a redirect only adds an address every drone must learn.

**Roles**

8. **The drone's advisor is the `advisor` tool** (Fable — two tiers above a
   Sonnet drone, one above the Opus lead), named in the brief with three
   moments. **Plan**: after orientation, before the first edit — the
   drone's context is smallest there, so it is the cheapest call and the one
   that saves the most. **Stuck**, at most once — a state, not a count: the
   drone can no longer state what it believes is wrong and what the next
   attempt will show, and is throwing things at the wall; tripping over a
   typo or a wrong path is not stuck. **Done**, only when no Sage runs: the
   advisor reviews the diff instead of the lead reading it. A call costs
   ~5× the drone's context in sonnet units, which is why the plan call is
   the default and the other two are conditional. A Sonnet that spent its
   stuck call, or `PULL`ed on something that was not a fork, is logged as a
   mis-tier. Its answer is one message:
   the straight route, or "stop — report `PULL`" when the unit hits an
   unresolved fork or a wall; a `PULL` takes the unit off the run and back
   to `Needs design`, and what it blocks is not dispatched. The advisor sees
   only the drone's context, so the done-call checks the unit and the lead
   still checks what spans units. `agent-cost` prices each advisor call and adds it to
   `priced`, so the Sage-vs-advisor comparison is on one axis.
9. **The lead reviews and lands.** `--stat` for the fence on every unit;
   the full diff only where the cross-unit overview is what's checked (a
   shared seam, anything a player would notice) — a drone's done-call
   reviewed the rest, cheaper than bloating the lead's context; one
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
    "never the full suite". Nothing the issue already says, nothing the
    drone already carries — and **the skill itself holds the digest of
    what a drone carries plus the report shape it returns, so the lead
    never opens `.claude/agents/drone.md`** (owner, 2026-09-27: "if you
    needed to read the drone contract that's a failure of the `swarm`
    skill"). The digest mirrors a file the lead will now never read: a
    change to the drone agent re-derives it.
13. **Brief in `prompt`; `name` for addressability; `subagent_type: "drone"`;
    `model` mandatory and equal to the ledger's tier.** No `isolation`
    parameter — the drone makes its own `mise` worktree. If a drone idles on
    its prompt, one `SendMessage` nudge, then the file-pointer brief is the
    fallback shape; log the idle in the ledger.
14. **Before every dispatch, in one Bash call: the ledger row, the kanban
    claim, and `mise run issue-drift -- <n>`.** The ledger (`docs/handoffs/
    swarm-<date>-<HHMM>.md`, gitignored, ≤1.5k tokens, read with `mise run
    ledger -- show` — never a path built from a date) is the at-most-once record
    and the relief briefing, and **its roster is written by commands, never
    by the lead remembering**. Its handle is the lead-session lineage in its
    header, never the date or an mtime: every `ledger` verb resolves to the
    file whose lineage holds the caller's session, so `/swarm` always starts
    its own run and another live ledger on disk is never a relief trigger —
    **the verb decides relief** (`/relief` runs `ledger -- adopt`, which
    appends to the lineage), and the run ends with `ledger -- close`, which
    archives it: `mise run ledger -- dispatch <n> <drone>
    <tier>` in the dispatch call (creates the file for a new run, prints the
    roster back so the read is free), `mise run ledger -- report <n>
    --branch <slug> [--plan] [--stuck] [--pull]` in the collect call, and
    `mise run land --closes <n>` writes the `landed <sha>` row itself;
    `ledger -- note <n> '…'` appends to a row's notes without touching its
    state (an idle, a poison line), since relief classifies units off the
    state column. The roster carries per unit the three advisor moments of law 8 as PLAN /
    STUCK / PULL columns plus `adv` / ctx / calls / priced from
    `agent-cost`; the prose under it (queue order, carried items, open
    owner calls) stays the lead's. The 09-30 run kept no ledger until the
    owner asked and then rebuilt it from transcripts: the skill's dispatch
    step only *read* the file (`cat … 2>/dev/null`, which also hid that it
    was missing) and "rewrite in place" was a prose bullet. Not a clerk
    teammate: the failure was remembering, not writing — a clerk still needs
    the lead to remember, and each of its replies wakes the lead. `mise
    gh-project -- status <n> in-progress` claims the issue; `issue-drift`
    is silent when the issue's stamped reading list still holds, prints
    the drifted entries otherwise (then one `Explore(model: haiku)`
    re-verifies them before the brief is written), and says `no stamp` on a
    pre-charter issue.
15. **Shared contracts land on master first.** A seam every unit overrides,
    a registry every unit appends to, a `.tres` every unit touches — the
    lead commits it before spawning; drones branch from the tip.
16. **One wave per message.** All `Agent` calls for a wave in one message;
    act on each completion as it arrives, never batch reports.

30. **A split shares one brief file.** When the lead splits one issue
    across drones, it writes one `docs/handoffs/swarm-brief-<n>.md`
    (gitignored) with the common part first and one short section per
    drone; each drone's `prompt` is the file path plus its section name, and
    the file's first line says whether the issue is still the spec (a split
    of a `Ready` issue: it is — the drone views it as usual) or the brief
    replaces it (the planner shape of law 11). Owner, 2026-09-30: "lead
    could split and write shared prompts -- 1 output consumed by >1 could be
    targeted at different parts while most is the same". It saves the lead's
    output tokens and keeps the parts consistent; the drones' read cost is
    unchanged.

31. **Whip relay mode is a report-address swap, nothing else.** When the
    launch prompt says *whip relay, train `<t>`* (see [whip](whip.md), law
    12), the lead's three human-facing moments become three verbs —
    `mise run whip -- relieve-me`, `done <sha> <n/m>`, `needs-owner <n>
    "<line>"` — which launch the relief, pass the baton to the next train
    or end the run, and note the item; a question becomes a stated
    assumption or a pull, and no other traffic exists. Every other law
    holds. v1 (2026-10-02) sent three `SendMessage` lines to a central
    `whip` session instead; probed then that a `--bg` session refuses a
    peer's instruction unless its launch prompt names the peer as
    principal, which is why the relay clauses still name the watchdog's
    and the owner's prompts as the lead's instructions.

**Collect and land**

17. **Read reports, not diffs.** A report is six lines — the sixth is `COST:` (ctx, calls, exchanges), the drone's own count, so the lead can judge resume vs retire and tier the next brief without waiting for `agent-cost` (owner, 2026-09-17: "drone must report ctx size or tool call count if known in report. Helps judge"); a wall of text is a
    drone-contract violation, not something to summarise.
18. **Per report: fence, content, tests — then branch.** Land it; fix a
    one-liner yourself then land; resume the drone with a sharp diagnosis;
    pull it — a `PULL` or a fork, back to `Needs design` per law 8 (owner,
    2026-09-30); or stop — the same blocker twice with no fork, `in-review`
    with a one-line comment — and serve the rest of the swarm.
19. **"Pre-existing failure" is a claim.** Check against a real `master` run
    before landing over it.
20. **`mise run land -- <branch> [--closes <n>]` is the only way onto
    master.** Serial by `flock`; rebases in the worktree; `check` +
    `test:dir`; `--closes` only on the final branch of a multi-unit issue.
    A non-zero is handed back to the drone once; twice is a stop. Its
    verdict is the exit code or a `LANDED` / `✗` line — a filter on its
    output must match both (`grep -E 'LANDED|✗|ERROR'`), never success alone.
21. **The full suite runs once per train**, after every branch of the batch
    is fast-forwarded, and only when the batch is runtime-observable
    (`.gd`/`.tscn` changed) — `check` for a scripts-only batch, nothing for
    docs. Red train → bisect by `test:dir` on merge points.
22. **After a new `class_name` lands, compare script counts** across the
    train's suite run — a missing or unstaged `.uid` is a test that silently
    never ran, and no cache predicate sees it. The cache needs no hand
    `refresh`: `mise run test*` refreshes it itself on `class_name` drift.
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
    refused). A stray worktree found at orientation (`.claude/worktrees/`
    included) is deleted, not carried as an owner question, once its branch
    is merged or nothing in it is worth mining — owner, 2026-10-01:
    "worktrees if merged or nothing of value left to mine from -> always
    delete".
26. **Always `git -C`**, never a bare `git` after a `cd`; explicit-path
    `git add`; `checkout -- .` a worktree that cold-imported before
    rebasing; re-read `master` before concluding a merge misbehaved — it
    moves under you.
27. **Never acknowledge a finished drone**; never infer from an idle that a
    drone's background command finished; relay reports in your own words,
    never paste diffs.

28. **The lead sweeps `poison:` lines before the gate** — greps them out of
    the ledger's reports, applies the one-liners itself in the main checkout
    as one docs commit, files the rest with `gh issue create`. No fix-drone, no manifest:
    one report in eleven issues does not pay for a dispatch shape. Revisit at
    five or more lines in one swarm.

29. **A genuinely hard unit gets a trap list before its drone starts.** For a
    bit-exact transliteration, a solver port, anything where a green suite
    would not catch the wrong answer: ask an idle peer session (`ListAgents`)
    for *where this will break* — not a plan, not a file summary — and (1)
    which files it holds so the drone stays clear. Say "if you're mid-task,
    answer (1) alone". Dispatch without waiting; the drone reads for its first
    stretch, so a list arriving minutes later still lands before code. Relay
    it verbatim into the brief; anything the peer flagged as *unverified* goes
    to the drone as an open question to resolve by reading, never as fact.

## Incident corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-07-30 | field | a named teammate returned "will receive instructions via mailbox" and idled; later runs measured 5/5 and 7/7 idles on the placeholder-prompt shape, 2/2 starts on a file-pointer brief | 13 |
| 2026-08-03 | two runs | one issue ≈ 10–20% of a rate-limit window; shedding six mid-flight drones cost ~10% alone; a run that succeeded came in at ~12%/unit with the formula predicting 1.4× that | 5 |
| 2026-09-17 | #918 swarmify | one stale-text report across the 2026-09-16 swarm's 11 issues; owner shrank the aggregated fix-drone proposal to a token + a lead sweep ("40 lines in drone description for that would be like 38 too many") | 28 |
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
| 2026-09-09 | #813 | A read-only peer produced 15 numbered traps in one turn; the drone named four it would have gotten wrong, including a sorted-`std::map` banking that was silently wrong only when one edge takes load from two pushed vertices in one substep. | 29 |
| 2026-09-19 | week of 09-14 | per-issue cost fell to ~5.5% of a window (owner, 2026-09-21: "due to updated swarmify mostly (better specs, map and seams provided, a lot less research needed to be done by implementer drones the first 40 tool calls etc)"); ledger 2026-09-19 corroborates: owner window 9% at start → 32% after 5 landed units (≈4.6%/issue). A snapshot, not a trend line — the window size moves with promotions, so compare `priced`, not % | 5 |
| 2026-09-27 | lead | the skill said "read `.claude/agents/drone.md` once"; the lead spent ~2.5k tokens on the full contract (start steps, economy, retiring, Sage flow) to learn what not to put in a brief — owner: "if you needed to read the drone contract that's a failure of the `swarm` skill" | 12 |
| 2026-09-19 | `f9` → `b6` | an Opus lead relieved at its 200k ceiling; the one in-flight drone was drained by redirecting it to the relief session's address — the last handover of that shape; the relief charter replaced the redirect with one outgoing wake per drone (ledger row + one-line ping), since the report reaches the outgoing regardless | 7 |
| 2026-09-27 | 10 units | 10 opus-tier units (two hubs, 3 waves, 4 drones resumed across waves for hot context, 1 Sage, 0 rejects, 16 review exchanges) landed + train-gated in ~40 min wall; owner: "43% of limit used" — a snapshot unit (law 5 text above), ≈4%/unit against 2026-08-03's ~12%/unit; lead finished at ~160k by delegating every sweep | 5, 6 |
| 2026-09-28 | #1179 tier experiment | owner: "try the experiment, ask it to let advisor have a pass when done"; Sonnet on #1179 (new channel + 7 re-pointed tests) vs #1178 (opus, comparable): 123 calls (90 cap) / Σctx 18.4M / 2.48M priced / 48 min vs 45 / 4.2M / 1.74M / 12 min — landed clean, ~40% dearer; overrun blamed on recovering from an early write to the main checkout | 6, 12 |
| 2026-09-29 | 3 sonnet + 2 opus | priced per 100 changed lines: opus 0.19M (#1190) / 0.20M (#1196), sonnet 0.37M (#1191) / 0.70M (#1082); both medium Sonnet units left stale characterization tests the lead re-pointed in the train; the 2-line #1107 leftovers unit at 125k was the only clean Sonnet win → owner, 2026-09-30: Sonnet for "small units or dumb units" | 6 |
| 2026-09-30 | ledger | the lead kept no ledger until the owner asked, then rebuilt it from transcripts; the dispatch step's Bash call only `cat`-ed the file and "rewrite in place" was prose → `mise run ledger` + `land` write the roster | 14 |
| 2026-09-30 | #1222 | ≥4 deliverables dispatched as one opus unit against law 3: 4.21M priced (23% of the run), did not land in its drone's budget; the relief lead finished it by hand → sizing moved to swarmify (law 27 there) with the lead's size net here | 3 |
| 2026-09-30 | lead cost | the swarm lead and a concurrent Fable session each blamed the other for the window; `agent-cost` could only see subagents (18.1M priced) — `--main` prices a main transcript | cost model |
| 2026-09-30 | owner | advisor law redrawn: "we shouldn't underestimate the power of the Advisor tool … so long Sonnet gets the plan right at the right time (and doesn't try 100 failed attempts first) that should help a lot"; a loop is not a count — the target is "i'm throwing things at a wall now", where drones "should raise their finger and be like 'help pls sensei, shed some light'"; with no Sage "a final advisor call might still be cheaper than bloating lead's context; though lead may have more of an overview"; an advisor answering a fork says stop and flag the lead, and the issue is "pulled from the swarm, sent back to the drawing board; possibly issues it blocks removed too" | 8, 9 |
| 2026-10-08 | 9 units | the lead filtered every `land` with `grep -E 'LANDED\|FAIL\|rror\|board'`; a red `test:dir` prints `✗ … is red` and `[land] ERROR`, neither matched, so the #1490 land failed silently — caught only because `LANDED` was missing | 20 |

## What the skill must not contain

- Any row above, any issue number, any date, the opencode column, the
  harness table, the Claude Code `<details>` block on harness worktrees
  (`isolation: "worktree"` is not used).
- The wake arithmetic, the window-percentage table, the worker-cost table.
- Whip's laws, its ledger verbs beyond the three a lead runs, or the
  watchdog (the whip-relay section names three verbs; the rest is
  [whip](whip.md)'s).
- The drone's standing rules themselves (they are in the agent; the skill
  carries only the digest of what a brief must not restate and the six-line
  report shape), `warp`'s rebase discipline (`land` mechanises it), or
  always-on rules.

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
  lands) and deserves its own charter.
