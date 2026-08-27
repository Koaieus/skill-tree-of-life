# Handoff — the next LAN swarm

Written against `ba6ab8a`, after the 2026-08-27 twelve-issue swarm.

**Authoritative:** the issues themselves, and `docs/FOCUS.md`. This file only
holds the thing neither of those holds — the **order** the remaining ten come
in, and which pairs cannot share a wave. Every decision below also lives in its
issue; if that stops being true, this file is wrong and the issue wins.

## State

`master` is green — **326 scripts, 2892 passing, 0 failing**, suite ~163s — and
was **15 commits ahead of `origin` and unpushed** at the time of writing. Twelve
issues merged carrying `Closes` lines that have **not fired yet**, so those
issues are still open on GitHub until someone pushes.

## The correction that matters most

**#597 is a HUB, not open design work.** Its 2026-08-27 swarmify pass settled
D1–D13; #641's body says outright *"Child 1 of #597 — nothing here is a new
decision, #597 D9 settled the model."* Every child sits in `Ready` with a
settled acceptance spec. The parent keeps a `design` label and sits outside
`Ready`; that is hub bookkeeping.

Two rows in `docs/FOCUS.md` claimed the opposite (open forks; a native
`blocked-by` on #349 that **does not exist in the GitHub API**). Both were
corrected in `ba6ab8a`. **This cost the last swarm real throughput** — two
children were audited as unstartable and left undispatched on the strength of
those rows. If a future audit reports "#597 blocks this", disbelieve it and
read #641's body.

## The DAG

```
#349 ──► #641 ──┬─► #642 ──► #643
                ├─► #638
                └─► #558

#626 ──► #627          (aura perf, independent lane)
#564                   (independent)
#621                   (independent — its #622 blocker SHIPPED)
```

Edges, each with what the later one needs:

- **#349 before #641** — #641 D12 and #642 both point at the top-level preset
  modules #349 creates (`procgen/modules/`, which does not exist yet).
- **#641 before #642 / #638 / #558** — #641 creates `session/scenario.gd`, the
  type the others point at. It was deliberately cut first for this reason.
- **#642 before #643** — #643 rides #642's override-merge mechanism.
- **#638 parallel with #642**, once #641 has landed.
- **#626 before #627** — #627 batches notifications on top of #626's work. The
  issues say explicitly: do not parallelise these.

**#349's real prerequisite is #327, not #597.** Its own body says "after
#324–#329 land"; five of those are closed and **#327 is the only one still
open** (rare.tres → hand-authored keystones). Judge #349 against #327.

## Wave plan, by file-disjointness

`effects/effect_context.gd` is the contended file of this set — **#621, #626,
#627 all touch it**, and #564 may. Never put two of them in one wave.

| Wave | Units | Why they co-exist |
|---|---|---|
| A | **#349** · **#621** · **#564** | `procgen/` vs `ui/tooltip_fan/`+`effects/` vs `command/`+`systems/`. Verify #564's `effects/effect_context.gd` touch at dispatch — one audit claims it, an earlier one did not. If real, drop #564 to wave B. |
| B | **#641** · **#626** | `session/` vs `effects/aura_effect.gd`. |
| C | **#642** · **#638** | Both need #641. #642 is `procgen/modules/`+`run_config`; #638 is the victory slot. |
| D | **#643** · **#558** · **#627** | `lobby_screen.gd` is *the most contended file in the lane* (#643's own note; #558, #638 and the #615/#616/#618 orchestration also touch it) — **#643 and #558 must not share a worker-wave on that file.** Sequence them. |

## Two issues returned to `Ready` from the last swarm

- **#621** — a draft exists on branch **`wt-tooltip-fan`**, commit `aef2165`,
  worktree kept. **Nothing in it has ever been run** — no test, no compile
  check. Its settled decisions are on the issue: build on the content-driven
  `PanelLayout` family (never the fixed `panel_base` envelope), hide at each
  operation's *neutral element* (`×0` must never hide; `SET` has none),
  acceptance 7 is the rolled-up row. **Give this its own `warp`** — it is a new
  panel + a new read path + a display rule, which is what made it run to ~400k
  tokens as a swarm second unit.
- **#564** — nothing was produced; worktree torn down. Its three located
  defects are recorded on the issue. Its audit's **line numbers are stale**:
  #556 landed a `_pre_roll` await and a `seat_policy` field inside
  `CommandApplier._drain`.

## Live numbers worth having in hand

- `mise run test:timings` now exists (#624) — per-script GUT timings parsed
  from `.godot/gut-last.xml`, no re-run needed.
- **25 of 326 scripts are ~74% of the suite; top 10 are ~54%.** Median script
  52ms.
- The tail is **not one phenomenon**: one top-3 script was a paced real-time
  wait (fixed, −29%, `8917a81`), two more are irreducible production-scale
  compute. #644's "~30% from fixture hygiene" figure does **not** generalise —
  re-derive per script.
- `test/unit/ui/**` is the untouched half of #644, and holds ~9 of the top 10
  (`test_level_up_flourish.gd` at 18.7s is the single slowest script).

## Dispatch mechanics that changed

Write each brief to a **file**, spawn with a one-line prompt pointing at it,
then `SendMessage` one line repeating the pointer. Workers then start
immediately (2/2) instead of stalling on a first idle (7/7 with the old
placeholder-prompt shape). Recorded in `.claude/skills/swarm/SKILL.md` and on
#595, with the small-sample caveat.

## Delete this file when

**#641 and #643 have both landed** — at that point the lane's order is spent
and the remaining issues stand on their own. Do not leave it in the tree after
that; a spent handoff is a trap.
