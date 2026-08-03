# Swarm resume — 2026-08-03, 22:30

Delete this file once the swarm is done.

## What happened

Six workers dispatched at 81% of the window; user stopped them at 93%. Nothing
merged. Two worktrees carry `wip` commits; the rest are empty and were reclaimed
by the stop.

**Re-read `.claude/skills/swarm/SKILL.md` first** — it was rewritten from this
run's failure (commit `7c90dc4`): there is now a budget gate with a sizing table,
and shared-context clustering is the *first* partition axis, not file-disjointness.
Resuming this exact plan verbatim would repeat the mistake it documents.

## Live state

Base: `7c90dc4` on `master`. Clean.

| worktree | branch tip | state |
|---|---|---|
| `.worktrees/wt-ai-lane` | `99beccd` | wip: partial #286 — `ShallowScoringPolicy` (new) + `ai_controller.gd` partway through the spend-all-SP loop. Unreviewed, untested. |
| `.worktrees/wt-stat-seam` | `d5eedbe` | wip: partial #340 — `skill_node.gd` + a new `test_node_local_bind.gd`. **`stats_system/stat_board.gd` is modified and the spec allows a comment ONLY there — verify that before trusting the diff.** |
| the other four | — | empty, nothing to recover. Remove them. |

Board: **#286 is `In progress`** (its wip is real). Everything else was reset to
`Ready`. Nothing is stuck.

## Resume plan — 2 workers, not 6

Per the new sizing table, and clustered by shared context:

1. **`stat-seam`** — resume the existing worktree (context is gone; it is a cold
   start onto a warm diff). #340 then #279. Owns `skill_node.gd`
   add/remove_local_modifier + `entity/core/**`.
2. **`hub-closers`** — one worker, both units: **#234** (last open child of #159)
   then **#341** (only open child of #238). Both are node/panel visuals, adjacent
   enough to share orientation. Shipping both closes two hubs that have been
   `In progress` for weeks — the highest-value thing on the board.

Then, only if budget remains: #362 (blocks #344 and the whole fan-geometry lane),
#174, #279.

## Decisions pinned during dispatch — reuse these, don't re-derive

- **#174**: fixed priority **MELEE > RANGED > MAGIC**, first valid wins, no scoring.
  Keep `_pick_hostile_target`'s first-match targeting.
- **#345 is NOT swarmable.** "Candidate treatments, none decided" + acceptance is a
  human eyeball. Needs a user call, not a drone.
- **#369 is NOT swarmable.** One-line bug report, no spec; the diagnosis is the
  expensive half.
- **#341's acceptance criteria 2 and 3** (14-state dial matrix, six-archetype
  legibility) are a human eyeball by the issue's own instruction. A drone commits
  the matrix scene; it does not certify it.
- `AllocationPolicy` **exists** at `procgen/placement/allocation_policy.gd` with
  `pick_next(entity, candidates, objective)`. Settled seam, don't redesign it.
- `gh issue view <n>` prints **nothing** in this environment. Always
  `--json body,comments -q '.body, (.comments[].body)'`.

## Board correction found mid-run

**#324 and #325 were already implemented on `master`** (commit `83c4330`) while
sitting in `Ready` — `stat_pool.gd` / `tier_ladder.gd` exist, `tier_pool.gd` /
`tier_def.gd` are deleted, `_roll_modifiers_v4` is in. Coverage lives in
`test_stat_draw.gd` + per-archetype pool tests rather than the issue's named
`test_stat_pool.gd` / `test_budget_draw.gd`. Closed as done. **Check #326 / #328 /
#329 the same way before dispatching them** — the same wave likely landed them too.
