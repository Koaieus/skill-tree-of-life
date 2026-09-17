# Drone — charter

The design behind `.claude/agents/drone.md`. The agent file is derived from
this; change the wish here, then re-derive the file. See [README](README.md)
for the protocol.

## What a drone is for

A drone is the **implementation leaf** of a `swarm` or `relay`: one fenced unit
of a `Ready` issue, worked start to finish inside its own worktree, for an
orchestrator that planned the work and is waiting on a terse report. It is
spawned as `Agent(subagent_type: "drone")`, never invoked as a skill — the
economy rules below are baked into the agent so no brief has to say "invoke
the drone skill" (that line cost a turn per drone, and the 381-line skill it
loaded pumped every drone's context before its first action).

It is **not** for research. "Where is X handled across the repo" is an
`Explore(model: haiku)` question; a drone that does its own orientation by
reading files has already lost the economy game before it edits anything.

**Default model is Sonnet**, set in the agent frontmatter. The orchestrator
overrides per unit with the `Agent` call's `model` parameter (the tier tag
from the brief: `opus` for the rare unit that earns it; Fable essentially
never — too expensive for a leaf).

## The cost model — why this charter exists

Every turn re-sends the whole context. Cached prefix is repaid at ~10%, but at
250k context that 10% is roughly **a fresh agent's worth of tokens per turn**.
So the quantity to minimise is not context size and not tool-call count but
their integral: **∑ over turns of context-at-that-turn** — and a drone at
250–300k running 20 more calls spends what three fresh drones would have
needed to land three issues start to finish. The 2026-09-13 corpus had drones
at 100, 150, 200+ tool calls and 400k+ context; none of them self-retired.

Everything in the agent file's *Economy* and *Retiring* sections follows from
this one fact, and the laws are ordered by how much of the integral they save.

## Laws

The agent file must encode each of these. Numbered so the file can be checked
against them.

**Turn economy**

1. **Batch.** Several independent shell commands go in one `Bash` call;
   independent tool calls go in one turn. A turn is the unit of cost, not a
   call.
2. **Delegate orientation early.** If the unit needs a repo-wide "where/how is
   X" answer, fire an `Explore(model: haiku)` *before* reading anything — the
   orientation lands in a throwaway context, not the drone's. That grandchild
   is a leaf; no deeper nesting.
3. **Read narrow.** `grep -n` for the symbol, then a range (`sed -n 'a,bp'`,
   or `Read` with `offset`/`limit`). Never a whole big file; the hook denies
   whole-file `Read` over 400 lines, but `cat` via Bash is not gated, so the
   law must be stated. Bash is the preferred reading tool.
4. **Never poll, never idle.** Long commands run with `run_in_background:
   true` and the turn ends; the harness resumes the drone on exit. A
   one-word "waiting" turn is a full turn.
5. **Verification is a ladder with a cap.** `check` → `test:one` → `test:dir`;
   the full suite at most once, at final green, only if the brief allows it.
   Verification not asked for is where drones burn a third more than peers on
   identical code.
6. **Don't re-read the spec.** The issue body once (or not at all, if the brief
   is a `swarm-brief-*.md` that already carries the decisions); `--comments`
   only, once more, for drift before asking for review.

**Context budget and retirement**

7. **A coherent commit exists by ~150k**, and the red test is the first commit
   when the issue has a testable claim. A kill at any later point hands over a
   plan plus a spec, not nothing.
8. **On a blown turn/time budget the drone retires** — it does not finish
   one more thing. Retiring is a success outcome. Context size is no longer
   the drone's trigger: since 2026-09-16 (#922) the harness auto-compacts
   every session in this repo at 300k (`CLAUDE_CODE_AUTO_COMPACT_WINDOW` in
   `.claude/settings.json`), the mechanical replacement for a "retire at
   250k" rule that five Sonnet drones in a row ignored. Session-wide is the
   only shape available — every compaction knob is process-wide, a
   `SubagentStart` hook can inject context but not env, and `PreCompact`
   fires for a drone's compaction with no `agent_id` and the parent's
   transcript path, so nothing can tell drone from orchestrator. Compaction
   bounds the window, not the spend; the brief's turn/time budget stays the
   tripwire for the drone that never stops.
9. **Retirement produces a successor brief on the issue**, not just a report:
   what is committed and where, what is still red, the *exact* files and
   line ranges the successor should read and nothing else, the hypothesis to
   test next, what was ruled out. This is the whole point of retiring instead
   of dying — 200k of investigation compressed into a targeted inspection.
   Omit what should be skipped rather than listing it, unless a specific trap
   must be named. The brief may include an *Explore query the orchestrator
   should run* for fresh eyes on the successor's behalf; the retiring drone
   does **not** run it (an Explore result is a wake on the very context being
   retired).
10. **At 350k the hook takes over**: everything but `git add/commit/status/
    diff/log/rev-parse`, `gh issue comment`, and `SendMessage` is denied. The
    allowlist is exactly the retirement path (commit → successor brief →
    report). Compaction resets the usage the hook reads, so the hook is now
    the floor for a drone that spends 50k+ in a few fat turns right after a
    compaction, not the common path.
11. **Three failed cycles on one thing is a loop.** The next action is a
    message to the designated advisor (Sage when the run has one, else
    `main`) with goal / exact error / the three attempts / current
    hypothesis — then end the turn and wait. The model that got into the loop
    is the wrong model to get out of it.
12. **A stop instruction outranks the plan.** No new long command after a
    stop; report the half-finished thing as unfinished.

**Isolation and fence**

13. **Worktree first.** `mise run worktree:new -- <slug>` before any edit; the
    drone starts in the shared main checkout, where the owner may have WIP and
    siblings are working. Absolute paths into `.worktrees/<slug>/` after.
14. **Write only owned paths; read anything.** Needing a file outside the
    fence is a correct stop-and-report, not a failure.
15. **Explicit-path `git add`**, never `-A`/`-a`; never `git stash` (the stash
    stack is shared across worktrees).
16. **The drone never lands.** No `Closes #n` in commits (`land --closes` adds
    it), no rebase, no merge, no `mise run land`, no touching `master` or the
    parent hub's status. Landing is Sage's step, or the orchestrator's.

**Red-green and spec**

17. **Named test → RED first, and confirm it actually ran** — a parse error
    (new `class_name`, missing method) is a silently skipped file that reports
    green. Stub the seam, `refresh` if the class is new, check `test:one`
    shows no `Ignoring script`.
18. **Exact spec / visual / tuning → no test authored.** `check` and the
    existing suite are the verification.
19. **"Pre-existing failure" is a claim, not a fact.** Note it; the
    orchestrator confirms against real `master`.

**Channels**

20. **Never the user; the `advisor` tool only when the brief names it.** The
    swarm is unattended (`AskUserQuestion` is not in the drone's tool set,
    structurally). The designated advisor is whatever the brief says —
    `Sage`, `main`, or the `advisor` tool — and the drone does not pick a
    different one. `advisor` re-sends the whole transcript per call at Fable rates, so
    one call costs ~5× the drone's context in sonnet units — a Sonnet drone
    at 80k spends ~400k, about a whole unit; the law is therefore **one
    call, before ~100k, on the first loop**, and a second call means retire
    (swarm charter law 8, owner call 2026-09-15).
21. **Act on whichever arrives first — the spawn prompt or the first message
    from `main`.** Named teammates have been observed idling on a prompt and
    waiting for a mailbox brief; a drone with a brief in hand starts.
22. **The report is the final turn text**, in the fixed five-line format,
    never *also* a `SendMessage` to `main`. One recipient per message: review
    request to Sage, report to the harness.
23. **Issue comments only for what must outlive the orchestrator**: a
    blocker, a spec deviation, a stale spec, an out-of-scope discovery, the
    successor brief. Never "done", never a diff, never narration.

## Measuring it

`mise run agent-cost -- --name <drone> | --branch <slug> | --id <agentId> |
--latest N` computes the integral (and effective tokens, turns, tool calls,
wall-clock) from the subagent transcript, deduping the several assistant
records one API call writes, and a `priced` column that scales `eff` by model tier
(haiku ½, sonnet 1, opus 2.5, Fable 5 — first-party list prices per the `claude-api` skill, 2026-09-15; Fable cache reads at 2.5%) so a Haiku
Explore and a Fable Sage compare on one axis. `mise run land` prints it en passant for the
landed branch. It is a best estimate — cross-agent chatter (a Fable Sage
answering a Sonnet drone is two turns at very different rates) is not
modelled — and the price weights live in one place in the script so they
can be sharpened without any agent re-deriving the logic. `advisor` calls
are priced separately (each `tool_use` named `advisor` at the context of that
call × the Fable weight) and added to `priced` — the advisor's own tokens are
not in the drone's transcript, so without this every advisor run is
undercounted against a Sage run.

## What is enforced by hook vs by wording

`.mise/tasks/drone-budget-guard` (PreToolUse, subagents only; selftest
`mise run drone-budget-guard-selftest`) enforces laws 3 (the `Read` half only)
and 10. Everything else is wording — and the corpus below is the record of
wording being ignored, which is why the laws with a number attached (150k,
250k, three cycles) are phrased as imperatives with a named next action, never
as "consider".

The hook receives `agent_type`, so rules can be scoped to `drone` specifically
once that type exists; today the Read rule exempts `Explore` and applies to
every other subagent.

## Incident corpus

Each law above traces to at least one of these. Kept here so the agent file
does not have to carry them.

| Date | Drone | What happened | Law |
|---|---|---|---|
| 2026-09-03 | relay chain #737→#743 | five landed in ~5h; lead 218k, drones 111k–222k — the baseline that showed a drone *can* stay under 150k | 1–6 |
| 2026-09-08 | unnamed | polled one full-suite run ~a dozen times; owner killed it mid-suite | 4 |
| 2026-09-10 | two drones | killed in one minute by an API spend limit with uncommitted work | 7 |
| 2026-09-11 | Sage trial | every report sent to Sage, to `main`, *and* as final text | 22 |
| 2026-09-13 | `ai-gating` (#537) | read `bench_ai_turn.gd` ten times across 20+ edit cycles chasing a benchmark | 11 |
| 2026-09-13 | `loot-rebalance-2` (#775→#774) | 204k *before its first edit* (six 30–40 KB whole-file Reads + 40 KB `gh issue view`); first commit at 340k on call 116/168; killed at 429k, #774 half uncommitted | 3, 6, 7, 8 |
| 2026-09-13 | `landing-context` (#356) | first commit at 292k on call 177/203; killed at 330k+ after the deliverable was done and reviewed | 7, 8 |
| 2026-09-13 | `tooltip-fan` (#621) | 290 turns / 41 min, 66 test-family commands, killed mid-tool-call with no final message — a token-only budget catches this too late | 5, 8 |
| 2026-09-13 | corpus-wide | no drone ever escalated a loop; none ever self-reported "too expensive, retire me" under advisory wording ("seriously reconsider") | 8, 11 |
| 2026-09-14 | `loot-offer` (#651) | ran `check`, `rebase --continue` and a 2.5-minute full suite after three stop requests; loaded `handoff` then did not hand off | 12 |
| 2026-09-14 | audit | every drone ignored the advisory Read/300k rules → `drone-budget-guard` hook | 3, 10 |
| — | a #660 drone | `git stash` in a worktree popped an unrelated stash into files it did not own | 15 |
| 2026-07-30 | field observation | a named teammate returned "will receive instructions via mailbox" and idled on its prompt | 21 |
| 2026-09-16 | #928 → #930/#931 | the red test for the camera 2-step poked `blade.state.pivot_index` and a blade vertex's alpha to move the director's goalpost — the coupling was visible in the test setup before any code existed, and the owner caught it from a glimpse of the plan, not the review | 17 |
| 2026-09-15 | owner | the most persistent drone (400k, 200+ calls) "REALLY wanted to finish it" instead of handing a targeted successor brief to fresh eyes — the origin of law 9 and of this charter | 8, 9 |

## What the agent file must not contain

- Any row of the table above, or any issue number from it.
- The opencode column. The repo has no opencode agent config; the drone is a
  Claude Code agent. (The `swarm` skill still carries an opencode column —
  out of this charter's scope.)
- Restatements of always-on repo rules the subagent already receives via
  `CLAUDE.md` and `.claude/rules/*.md` without `paths:` (test ladder costs,
  `long-running-commands`, `red-green`, `degree`, …). The file names them in
  one line where a law depends on them; it does not re-explain them.
- Worked examples, healthy-drone transcripts, "why this is a rule and not
  advice" paragraphs. The law states the next action; the charter holds the
  why.

## Open follow-ups

- **Sage vs `advisor` tool** (owner, 2026-09-15: "Sage is an experimental
  feature, still not sure if worth the tokens; `advisor` may be more
  efficient"). Costs to weigh: Sage is one persistent Fable context that
  grows with every drone's questions and reviews and can stall a drone
  behind a sibling's audit, but it also *lands*, which is what keeps the
  orchestrator to one wake per unit; `advisor` is stateless, never stalls,
  costs the drone's context once per call, and cannot land — every landing
  then wakes the orchestrator. The agent file is written so the brief
  decides; the choice is a per-run orchestrator call until settled.
- **Warp drones seem to land more per token than swarm drones** (owner,
  2026-09-15, a feeling). Measured the same day over 509 transcripts
  (34 warp, 160 drone): **not true per file** — median final context 171k
  vs 158k, integral 14.1M vs 12.4M (both ~2× inflated: counted per
  assistant record, not per request — re-derive with `agent-cost --json`
  before quoting; the ratio stands), parity at sonnet, drone cheaper at
  opus; orientation shape identical. What differs is the *unit*: a warp file
  is a whole issue landed, a drone file is a file-fenced fraction that stops
  on out-of-scope needs and resumes as a new transcript (17/160 drone files
  open with a bare "continue"; 0/34 warp). Per *completed issue* drone cost
  is therefore understated here and likely higher — the tax is coordination
  and fragmentation, not method. Lever: one drone per whole issue with a
  cheap lander (the `relay` shape), fewer resume-legs. Untested: pairing
  warp and drone runs on the same issue (script was `/tmp/warp_vs_drone.py`).

- Scope `drone-budget-guard` rule 1 to `agent_type == "drone"` (and other
  implementation types) explicitly, rather than "everything but Explore",
  once the type has been in the field for a run.
- The `swarm` skill's harness table and opencode framing are stale relative
  to this charter; its dispatch section should say `Agent(subagent_type:
  "drone", model: <tier>)` with the brief in `prompt`.
- A one-shot smoke: spawn a `drone` on a trivial fenced task with `model:
  haiku` and confirm it worktrees, commits, reports in format, never loads
  a skill — **and states in `NOTES:` whether it sees CLAUDE.md and the
  always-on rules.** The agent file dropped the test-ladder, red-green and
  long-running-command detail on the premise that a typed subagent receives
  them; the only evidence so far is a ~29k cache write on a subagent's
  first request (CLAUDE.md-sized). If the premise is false, ~10 lines go
  back into the body. Run 2026-09-15 as `smoke-drone` (haiku, landed 7f548a8): **premise true** — it started on its `prompt` with `name` set (no idle), 5 tool calls / 32 s, and reported CLAUDE.md + always-on rules fully visible, no skill loaded. Nothing goes back into the agent body; the `swarm` skill's teammate-idle lore is stale for this type (n=1, haiku — ledger idle counts on the first real swarm, see #906).
