---
id: 0017
title: Damage, armor, health, ranges and hop counts are INT stats; a merged (node-local) read floors exactly as a bare one
status: accepted
date: 2026-09-15
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#895"
  - "#890"
  - "stats_system/stat.gd"
  - "combat/node_combat.gd"
  - "entity/core/ninja_core.tres"
  - "entity/core/serpent_core.tres"
tags: [stats, balance, combat, design]
---

# ADR 0017 — Damage, armor, health, ranges and hop counts are INT stats; a merged read floors exactly as a bare one

## Context

ADR 0016 decision 2 made an INT scalar stat floor its finished total once, in
`Stat._coerce`. #895 found the floor never reached the **node-local** read:
`NodeCombat.get_local_value` merged entity + node bins through
`ModifierBins.compute` and returned the raw float, so `blade_damage` read
`8.5` on a spiked node where the wielder's own read said `8`. Fixing that
seam widened the blast radius to every INT stat an aura scales per node —
`armor`, `vision_range`, `sensor_range`, `ranged_damage` — and 12
characterisation tests had pinned those fractional local values (`+0.5`
armor at one hop, `6.67` vision under blindness).

That put a question on the table the INT defs only answered implicitly:
*are these INT on purpose, or should the stats an aura scales be FLOAT so a
falloff stays smooth?*

## Decision

1. **Damage (`blade_damage`, `spell_damage`, `ranged_damage`), `armor`,
   health and hop counts (`sensor_range`) are INT stats, by design.** Owner,
   2026-09-15: *"damage values are all INT, armor reduces it too (as an INT)
   during mitigation, all int-on-int action. just the modifiers in the
   StatBins that produce the final values may be floats."* Health is INT
   (core and node), so everything that adds to or subtracts from it is too.
   `sensor_range` is a hop count — *"100% an INT"*.
2. **`vision_range` stays INT although it is a pixel distance.** It *could*
   be FLOAT; it is INT for legibility — *"for users a sub-pixel fraction is
   quite meaningless (1322 vs 1322.123 — I'd pick the former for clarity)"*.
3. **A merged read floors exactly as a bare one.** There is one door for
   composing a stat with overlay bins — `Stat.get_value_with(overlays)` —
   and it coerces to the def's `value_type` after the single fold, the same
   as `get_value()`. Nothing else calls `ModifierBins.compute` on a stat's
   behalf. Fractions live in the bins; the *stat* is the integer.
4. **A per-node aura on an INT stat is therefore authored in whole units at
   the distances that matter.** A `+0.5/hop` contribution floors to nothing
   at one hop, and two consecutive hops can read the same number. The Ninja's
   falloff aura sets `value == max_hops` so it reads `N, N-1, …, 1, 0`; the
   Serpent's hop buff moved from `+0.5/hop` to `+1/hop`. *"Hops are int,
   values also int → always int, measurable diffs."*

## Consequences

- **Small fractional aura contributions vanish.** On a straight line the
  Serpent's armor at one hop is `+1 − 0.5 → 0` — the spatial penalty biting
  exactly where the class description says it should. When a value floors to
  zero where the design wanted a difference, the fix is the *authored* value
  (seed, base, or modifier magnitude — which one depends on the stat's
  intent), never a FLOAT def and never a floor moved earlier in the pipeline.
- **A `% increased` penalty on a small INT total barely moves it** — the
  Serpent's `−1% increased damage × 0.005/px` is `−0.5%` at 100px, invisible
  under the floor until totals are large. Tuning, not a defect; to be
  playtested.
- **Tests assert floored local values.** The 12 re-pointed asserts (#895)
  carry a `#890/#895` note each; a new test that reads a node-local INT stat
  expects an integer.
- **Pools keep rounding their own `current`** (ADR 0016), and the defs that
  are FLOAT today — `node_combat_health` (the per-node pool's stored
  representation), `node_healing` / `node_healing_ramp`, `crit_*`, the blade
  speed knobs, the health *scaling* factors — are untouched by this record:
  they are rates, factors and stored representations, not the quantities
  players read and trade blows in.

## Alternatives considered

### Flip `armor` / `vision_range` / `sensor_range` / `ranged_damage` to FLOAT
Keeps every aura falloff smooth and every existing assert green. **Why it
lost:** contradicts decision 1's model — mitigation would be float-on-int,
`sensor_range` would be a fractional hop count, and `blade_damage`'s own def
text (`+1 per 20 STR`) reads INT by design. It also reintroduces the exact
display problem (`+39.97 STR`) #890 set out to end.

### Leave the node-local path un-floored
Zero test churn; the entity read floors, the node read does not. **Why it
lost:** two answers to one question — `SkillNode.get_local_value` and
`Entity.stat_board.x.get_value()` disagreeing on the same node's blade damage
is the bug #895 was filed on, and it would make every per-node number a
parallel mirror of the stat pipeline with its own rounding.

### Floor each aura contribution before the bins
Would keep `+0.5/hop` legible as `+0, +1, +1, +2`. **Why it lost:** it is
the stair ADR 0016 just removed — a floor before the bins turns every
multiplier back into a burst.
