---
description: Stat system quick-reference — pipeline, stat IDs (grep), intrinsic scaling, gotchas
---

# Stat system reference

**Keep current.** Any change to the stat system — new stat, new formula type, modified pipeline, new pool or modifier class, new intrinsic scaling rule — must be followed by updating this rule.

## Modifier pipeline

`(base + ADD_BASE) × (1 + INCREASE/100) × MULTIPLY + ADD_BONUS`

- **SET** short-circuits everything; highest `priority` wins, last-in breaks ties at equal priority.
- **INCREASE** sums additively (PoE-style). Five +20% = ×2.0, NOT (1.2)⁵.

## Stat IDs

Run to list all current stat IDs:
```
grep -h "^id = " stats_system/list/*.tres | sort
```

`skill_points` is `SkillPointStat` (PoolStat subclass) with a `wounded` bucket: `wound(n)` = forced dealloc (attack); `heal(n)` = restore wounded → current; `refund(n)` = voluntary dealloc. Not interchangeable.

## Intrinsic scaling (entity/default_entity_board.tres)

These are `DerivedModifierDef` entries wired as `intrinsic_modifiers` on the default board — all entities get them. **Update this table when adding or changing a derived modifier.**

| Input stat | Target stat | Formula |
|---|---|---|
| `perception` | `vision_range` | `floor(PER / 10.0)` ADD_BASE |
| `intelligence` | `mana_max` | `floor(INT / 10.0)` ADD_BASE |
| `intelligence` | `mana_per_turn` | `floor(log(max(1, INT)))` ADD_BASE |

## Gotchas

- **DerivedModifierDef must not be shared across entities.** Always `.duplicate(true)` before `add_modifier()`. Intrinsics are safe — `apply_intrinsics()` auto-duplicates them.
- **Pool cap is a sibling stat, not a sub-property.** Target `&"health_max"`, not `&"health.max"`.
- **StatBoard field name must match the stat's `id` string.** `get_stat(id)` calls `Object.get(id)` — renaming either without the other silently breaks lookup.
- **Stat keys are currently GDScript objects (`get_script()`), not `StringName`.** Do not rename or move stat files without updating all `StatModifier.stat_key` references. v2 will use `StringName`; prefer `StringName` for any new stat work.
