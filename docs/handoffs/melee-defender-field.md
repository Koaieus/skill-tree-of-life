# Handoff — the melee defender-field chain (#807/#808 → #809/#810/#811)

Written 2026-09-09. **Delete this file once #796 lands** — it is scaffolding, not a record.
Everything durable is already in the issues, the ADR, the rule files and the commits below.

## What landed

Local `master`, **not pushed** (see "Push decision"):

| sha | issue | what |
|---|---|---|
| `cbd22fa` | #809 | induced-edge + exclude walks stop scanning the whole graph |
| `18bbd4d` | #773 | a non-geometric `ThresholdFormula` names its ladder, not a false ratio |
| `ebeea82` | #810 | `StatBoard.stat_created` hook; `SkillNode` drives collision bits off it |
| `8f36efb` | — | rule-file gap from #810's gate (`.claude/rules/stats-system.md`) |
| `ad1fa77` | #811 | one physics-built defender field replaces three contact models |

`ca520cb` and earlier on this branch came from a **parallel session**, not this chain.

## The one decision worth not re-deriving

`docs/adr/0014-one-physics-built-defender-field.md` is the home. Short version: melee had
**three** hand-rolled implementations of "blade vertex disc / rim-trimmed edge capsule vs node
disc" (`BladeHitScan` via the physics server, `BladeSwingClock.sense` analytic per sample,
`BladeObstacleField.project` analytic per solver iteration), kept in sync by a shared const and
a comment. #811 collapsed the analytic pair onto one physics-built immutable zone set.

The seam that made it possible, and that #808's body denies: **the only off-thread
`BladeSim.simulate` in the repo is `ai_blade_rollout.gd:293`.** Everything else is main thread.
So the field is *built* with physics on the main thread and *consumed* as plain arrays anywhere.
The ADR supersedes the "Two sensing models, deliberately" section that used to argue otherwise.

## Open, in dependency order

- **#796** — the next one. `Ready`, **not dispatched**; see below.
- **#812** — `stat_created` has one emit site but `_extra_stats` has two writers
  (`NodeStatBoard._mint_pool` mints silently). `Ready`, no deps.
- **#813** — native backend has no constraint hook, so more swings take the GDScript path
  now that every defender-adjacent swing has a field (`blade_sim.gd:212`). `Ready`.
- **#814** — a defender the physics space has not seen yet silently does not defend. The
  new silent-failure mode #811 traded in. `Ready`.

## Before dispatching #796, read this

**Its body's "What to do" is superseded by its own comments.** The body proposes
`WorkerThreadPool`; comment 3 supersedes that and is the real spec:

1. **Peer half is nearly free.** Per ADR 0002 a peer's resimulation is *draw-only* — every
   damage number, pop and hit comes off the `AttackRecord`. So peer sim fidelity is a
   **correctness-free knob**: `substeps=1`, length scaling off, still bit-identical outcomes.
   That should be a graphics setting, and it means #790's 4x need never be paid by a spectator.
2. **Authority half wants time-slicing, not threading.** `WorkerThreadPool` helps a many-core
   box and *hurts* the 2-core budget CPU that is the actual worry. Slicing ~5 ms per frame
   across #559's staging beat gives a hard frame-budget guarantee by construction.
3. There is a 4th comment on #796 (an owner architecture answer) that was **never read in this
   session**. Read it before briefing anyone.

**#811 changed #796's arithmetic in both directions:**
- Easier: the only physics call is now one main-thread `BladeDefenderZones.query()` cleanly
  separated from a solver that reads plain arrays, and the per-pivot zone set is immutable —
  a sliced solver can resume across frames without re-querying or re-validating anything.
- Harder: `blade_sim.gd:212` gates the native backend on `clock == null and obstacles == null`,
  so more swings now take the GDScript path. That is #813.

## Numbers that cost real effort to get — do not re-measure

- **Carriers on `first_level` (800 nodes, seed `0x57A17EE`): 114 `swing_drag`, 89 `deflection`,
  18 both, 185 distinct.** This is what killed the "carriers are a handful, so the cull can be
  as generous as correctness wants" claim in #808's comment — `sense()` was O(zones) per sample,
  so a generous field cost **+29%** on blade 4 until an AABB broad phase was added inside
  `project()`.
- `build_defender_zones` **36 us**, replacing 1744 + 1701 us.
- Coarse pass at 192 proposals: **12682 us** shared per-pivot, vs 18447 us per-proposal.
- `AiBladeRollout._coarse_rank_and_select` calls `build_blade_state()` **per proposal** on the
  calling thread (`ai_blade_rollout.gd:286`) — up to 192x. `bench_ai_turn.gd` never caught this
  because it runs #797's **4-node** fixture.

## Process notes for whoever runs the next chain

- **A half-loaded GDExtension makes the whole suite look catastrophically broken.** The first
  final-suite run reported **170 failing / 426 scripts / 0 pending** on a tree whose own
  worktree had been green. Signature: `Nonexistent function 'new' in base 'GDScript'`, fewer
  scripts than expected, and pendings *vanishing*. `mise run refresh` fixed it while correctly
  reporting "nothing changed" — the class cache was never the problem. The real cause was the
  parallel session's `c4032e4` supplying the native library mid-flight, leaving the extension
  half-loaded. Re-run before believing a mass failure, and read the **failing set**, not the
  count. (The clean re-run: 0 failing, 4050 passed, 434 scripts, 1 pending.)
- **Confirm a drone is idle before `worktree:rm`.** Tearing #810's worktree down under a
  running `godot` produced a phantom "4 failing" and killed its post-rebase verification.
- **Both Sonnet drones stalled** by ending a turn with "waiting for the background run to
  finish" — a full model turn spent saying nothing, ~20k context each. An explicit
  prohibition in the brief fixed it for the Opus drone. Worth folding into the `relay` skill.
- Check the rule-file obligation **at the gate**, not after. #810 changed `StatBoard` and
  CLAUDE.md requires `.claude/rules/stats-system.md` stay current; that was caught late.

## Push decision — outstanding, owner's call

Local `master` is ahead of `origin` and carries a **parallel session's** `ca520cb` as well as
this chain. Per `.claude/rules/`, `push origin master` publishes whatever anyone landed, so
nothing was pushed. Push an explicit sha, or confirm the parallel work is ready to publish.
