# Balance harness (#268)

**Informative only — an order-of-magnitude smell test for runaway or non-fun
values. Not a source of truth and never a build gate** (amendment, 2026-08-03).
Real balance is too complex to model faithfully; nobody should read a harness
number here as "the correct value." A human supplies "this plays nice" — the
harness supplies cold, re-runnable numbers and a place to watch a handful of
named ratios drift.

## What this is

An evaluator, not a search: a fixed set of named scenario fixtures
(`balance_scenarios.gd`), each assembling real `Entity`/`SkillNode` instances
via `preload(...).instantiate()` and driving them through the real allocation
(`AllocationSystem`), damage (`Mitigation.apply` / `SkillNode.take_damage`),
and turn-upkeep (`Entity._on_turn_started`) code paths — never a
reimplementation of a combat formula. See `docs/domain/` and
`.claude/rules/stats-system.md` for what those paths actually do.

## Running it

```
mise run balance                                              # full table + snapshot
mise run balance:sensitivity -- mirror_L20 dexterity 5 40 5   # 1-D slice
```

`mise run balance` always exits 0 — a non-zero exit is reserved for the
harness crashing, never for an `OUT` invariant reading (see `invariants.json`'s
header).

## Files

- `balance_fixture.gd` — builds one entity+territory at a target level by
  driving the real level-up path (`Entity._on_xp_replenished`), not by
  re-deriving the D-16 owned-node-count formula. That formula has already
  moved twice (see #268's "your axes moved" comment); driving it for real
  means a future change is picked up automatically.
- `balance_scenarios.gd` — the named scenario fixtures + readout computation.
- `balance_invariants.gd` + `invariants.json` — the ratio-invariant config
  and checker. **Every range ships `TBD`** — filling one in is a #248
  balance-pinning-session decision, never an implementing agent's call (D-13).
- `balance_harness.gd` — glues the above together, formats the table, writes
  the snapshot.
- `run_balance.gd` / `run_sensitivity.gd` — the two `SceneTree` entry points
  `mise.toml`'s tasks invoke.
- `snapshot.md` — committed output of the last `mise run balance` run. A
  balance change shows up as a diff here.

## Snapshot staleness — this is not #274's job

`tools/balance/**` is not in #274's files-owned list. When #274 lands
(`spell_damage` gets a real default, currently `0.0`/absent — every spell
seed changes), the committed `snapshot.md` goes stale against the new spell
numbers. **Refreshing it is a follow-up task, not #274's responsibility** —
#274 must not widen its ownership to touch this directory. Re-run
`mise run balance` and commit the new snapshot once #274 lands (and again
after any future change to a formula this harness reads).

## Assumptions worth knowing, not just reading in a code comment

- **AP cost is read as 1 for both the melee and ranged channel.** Neither
  `attack/plan/melee_attack_plan.gd` nor `attack/plan/ranged_attack_plan.gd`
  ever sets `AttackOutcome.ap_cost` away from its class default (`1`), so
  `damage_per_ap_*` and `melee_dpa_over_ranged_dpa` are computed as plain
  mitigated per-hit damage. If a future change gives either channel a
  non-default AP cost, this harness needs to read it from the real
  `AttackOutcome` a resolved plan produces, not keep assuming 1.
- **`aura_coverage_fraction` is sensitive to branching factor, on purpose.**
  `core_adjacent_aura_L50` builds its defender on a k-ary tree (branching
  factor 3, `topology_branching_factor` in its row), not the straight chain
  every other scenario uses. A chain caps a range-3 aura at exactly 3 covered
  nodes forever regardless of level, which would make the fraction decay
  toward zero as a pure artifact of level rather than of territory shape —
  see #268 review. Reading the fraction without the branching factor next to
  it is reading half the number.
- **`melee_dpa_over_ranged_dpa` needs a fixture with STR ≠ DEX to mean
  anything.** Every mirror scenario uses plain `BalancedCore`, where the two
  attributes track together and the ratio reads 1.000 by construction.
  `asymmetric_snipe_L20_vs_L80`'s attacker gets an explicit DEX+30/STR−5 skew
  so this invariant (sourced from that scenario in `invariants.json`) has
  something to actually move against.

## Known gaps (deliberate — see #268's NOTES)

- A magic-channel readout now exists (#366): `tools/balance/balance_scenarios.gd`
  carries a `magic_mirror_L20` fixture, a real `_SPELL_POOL` of `SpellDef`s,
  and `spell_dpa_best` / `spell_dpa_over_melee_dpa` invariants. Spell reach's
  ×2 hard cap (D-18) is still worth a dedicated fixture once a scenario
  exercises it; the existing `mirror_L20` doesn't push the cap.
- The bunker-stacking observation previously filed on #367 — that two
  `bunker_addon.tscn` instances on one node do NOT stack because Godot's
  PackedScene cache reuses the same `StatModifier` sub-resource across
  instantiations and `Stat.add_modifier` dedupes by instance — has been
  **resolved as a side-effect of #376**: `_attach_addon` now clones a
  scene-instantiated addon's modifiers before adding them, so each bunker
  gets its own modifier and they stack as authored intent (+5 +5 = +10).
  The `bunker_stack_L20` fixture's `bunker_stack_armor` readout therefore
  moves 5 → 10 on a #376-headed master. Worth re-pinning the
  `armor_saturation_against_floor` range against the new stacking baseline
  once the invariant thresholds get pinned (#248) — and confirming two
  bunkers stacking is the intended design, not a new regression.
- XP-curve and procgen↔level readouts are undefined until #248 pins those
  axes.
- Filling in real threshold values is a #248 pinning-session task, not this
  harness's.
