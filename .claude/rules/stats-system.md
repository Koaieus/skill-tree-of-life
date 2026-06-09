---
description: Stat system quick-reference — pipeline, stat IDs (grep), intrinsic scaling, gotchas
---

# Stat system reference

**Keep current.** Any change to the stat system — new stat, new formula type, modified pipeline, new pool or modifier class, new intrinsic scaling rule — must be followed by updating this rule.

## Modifier pipeline

`(base + ADD_BASE) × (1 + INCREASE/100) × MULTIPLY + ADD_BONUS`

- **SET** short-circuits everything; highest `priority` wins, last-in breaks ties at equal priority.
- **INCREASE** sums additively (PoE-style). Five +20% = ×2.0, NOT (1.2)⁵.

## Pool stats

`PoolStat extends ScalarStat`. The stat IS the cap — `get_value()` / `.value` returns the modifier-computed maximum. `.current` is the ephemeral game state (damage/heal, not the modifier system). Modifiers always target the pool id directly (e.g. `"health"`, `"mana"`); there are no `*_max` sibling stats or IDs.

`heal_on_max_increase` fires automatically via `add/remove_modifier` overrides — no external plumbing.

`skill_points` is `SkillPointStat` (PoolStat subclass) with a `wounded` bucket: `wound(n)` = forced dealloc (attack); `heal(n)` = restore wounded → current; `refund(n)` = voluntary dealloc. Not interchangeable.

## Stat IDs

Run to list all current stat IDs:
```
grep -h "^id = " entity/stats/list/*.tres | sort
```

## Intrinsic scaling (entity/default_entity_board.tres)

These are `DerivedModifierDef` sub-resources wired as `intrinsic_modifiers` on the default board — all entities get them. Keep them inline in the board .tres (not separate files). **Update this table when adding or changing a derived modifier.**

| Input stat | Target stat | Op | Formula |
|---|---|---|---|
| `perception` | `vision_range` | INCREASE | `PER × 2.0` (LinearFormula scale=2) — at PER=3 → +6% |
| `intelligence` | `mana` | ADD_BASE | `floor(INT / 10.0)` |
| `intelligence` | `mana_per_turn` | ADD_BASE | `floor(log10(max(1e-5, INT)))` |
| `wisdom` | `xp_per_turn` | ADD_BASE | `floor(log10(max(1e-5, WIS)))` |
| `dexterity` | `sensor_range` | ADD_BASE | `floor(DEX / 10.0)` |

## Gotchas

- **DerivedModifierDef must not be shared across entities.** Always `.duplicate(true)` before `add_modifier()`. Intrinsics are safe — `apply_intrinsics()` auto-duplicates them.
- **Pool modifiers target the pool id, not a `_max` suffix.** `"health"` targets the health cap. `"health_max"` doesn't exist.
- **`max` is a GDScript built-in.** Never name a property or variable `max` on PoolStat or its subclasses — it shadows `max()` in all subclass methods. Use `.value` for the cap.
- **StatBoard field name must match the stat's `id` string.** `get_stat(id)` calls `Object.get(id)` — renaming either without the other silently breaks lookup.

## Visualizer (editor plugin)

`addons/stat_board_visualizer/` — Inspector button on any `StatBoard` .tres mounts it in the "StatBoard" bottom panel. Runtime F3 overlay is `ui/stat_board_overlay/`.

- **Add modifiers** — toolbar `+` button OR drag a stat's port to another stat's port (presets as Linear `source × scale`). Disk-backed boards persist via `ResourceSaver`; runtime boards mutate in memory only.
- **Expression formula inputs are auto-derived.** `ExpressionFormula.detect_inputs(text, candidates)` uses word-boundary regex; the dialog live-validates while typing.
