---
description: Stat system quick-reference — pipeline, all stat IDs, gotchas
---

# Stat system reference

**Keep current.** Any change to the stat system — new stat, new formula type, modified pipeline, new pool or modifier class — must be followed by updating this rule. Its value is that it isn't stale.

## Modifier pipeline

`(base + ADD_BASE) × (1 + INCREASE/100) × MULTIPLY + ADD_BONUS`

- **SET** short-circuits everything; highest `priority` wins, last-in breaks ties at equal priority.
- **INCREASE** sums additively (PoE-style). Five +20% = ×2.0, NOT (1.2)⁵.

## Stat IDs

**Scalars:** `strength` · `dexterity` · `intelligence` · `wisdom` · `perception` · `node_health` · `initiative_speed` · `xp_per_turn` · `vision_range` · `sensor_range`

**Pools (current + sibling cap):** `health`/`health_max` · `xp`/`xp_max` · `skill_points`/`skill_points_max` · `action_points`/`action_points_max` · `deallocation_points`/`deallocation_points_max`

Defaults: attributes 10 · health 10/10 · XP 0/5 · SP 1/3 · AP 2/2 · DP 3/3 · vision_range 400px · initiative_speed 10 · sensor_range 0.

`skill_points` is `SkillPointStat` (PoolStat subclass) with a `wounded` bucket: `wound(n)` = forced dealloc (attack); `heal(n)` = restore wounded → current; `refund(n)` = voluntary dealloc. Not interchangeable.

## Gotchas

- **DerivedModifierDef must not be shared across entities.** Always `.duplicate(true)` before `add_modifier()`. Intrinsics are safe — `apply_intrinsics()` auto-duplicates them.
- **Pool cap is a sibling stat, not a sub-property.** Target `&"health_max"`, not `&"health.max"`.
- **StatBoard field name must match the stat's `id` string.** `get_stat(id)` calls `Object.get(id)` — renaming either without the other silently breaks lookup.
