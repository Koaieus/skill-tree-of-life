---
description: Stat system quick-reference — pipeline, stat IDs (grep), intrinsic scaling, gotchas
---

# Stat system reference

**Keep current.** Any change to the stat system — new stat, new formula type, modified pipeline, new pool or modifier class, new intrinsic scaling rule — must be followed by updating this rule.

## Modifier pipeline

`(base + ADD_BASE) × (1 + INCREASE/100) × MULTIPLY + ADD_BONUS`

- **SET** short-circuits everything; highest `priority` wins, last-in breaks ties at equal priority.
- **INCREASE** sums additively (PoE-style). Five +20% = ×2.0, NOT (1.2)⁵.

## Local stats (per-node overrides)

`LocalStat extends Stat` (`stats_system/local_stat.gd`) is a per-node stat that reads `entity_stat.base_value` and merges entity + node bins via `ModifierBins.compute()` — avoids double-applying INCREASE/MULTIPLY that a naive pipeline-chain would. Lazy-created on `SkillNode.get_local_stat(id)`, rebinds on `owner_changed`.

**SET tiebreak:** highest priority wins; at equal priority **last source listed wins**. `LocalStat` orders `[entity.bins, self.bins]` so a local SET beats an entity SET at the same priority.

Any stat id can be localized; convention picks the meaningful ones (currently `node_health`, `range`). If the owning entity's board lacks the stat (older hand-authored boards that predate it), `SkillNode.get_local_stat` falls back to `StatRegistry.get_def(id).default_value` so reads return something sensible — but scaling modifiers won't apply until the board catches up.

## Pool stats

`PoolStat extends ScalarStat`. The stat IS the cap — `get_value()` / `.value` returns the modifier-computed maximum. `.current` is the ephemeral game state (damage/heal, not the modifier system). Modifiers always target the pool id directly (e.g. `"health"`, `"mana"`); there are no `*_max` sibling stats or IDs.

`heal_on_max_increase` fires automatically via `add/remove_modifier` overrides — no external plumbing.

`skill_points` is `SkillPointStat` (PoolStat subclass) with **four buckets**: `used + current + wounded + staked == max` (identity — get_value() returns the sum, modifiers and base_value are bypassed). Operations:

| Method | Effect | Mints? |
|---|---|---|
| `spend(n)` | current → used | no |
| `refund(n)` | used → current (voluntary dealloc) | no |
| `wound(n)` | used → wounded (forced dealloc, AttackSystem cascade) | no |
| `heal(n)` | wounded → current (turn-start) | no |
| `stake(n)` | current → staked (raise per-node alloc cap) | no |
| `extract(n)` | staked → current (recover a stake) | no |
| **`claim(n)`** | mint into used (force_allocate / scripted setup) | **yes** |
| **`grant(n)`** | mint into current (level-up) | **yes** |

Order discipline inside transfers: when raising current (refund/heal/extract), call `set_current()` **first** then drop the source bucket — otherwise PoolStat.set_current clamps to the pre-write cap and silently eats 1 SP. The `grant()` mint writes `current` directly (bypasses the clamp) so max can grow.

Scene-authored ownership (e.g. dev_sandbox `owned_by = NodePath(...)`) doesn't go through `force_allocate`, so `AllocationSystem.register_scene_authored_ownership()` walks the graph at GameRoot._ready and claims for each pre-owned node. Procgen content runs later and claims via force_allocate — no double-count.

**Do not** push StatModifierDefs at `skill_points`. The override of get_value bypasses the modifier pipeline; modifiers would be silently inert. Mint via `grant(n)` instead, or `claim(n)` for locked-in SP.

## Turn-start upkeep

`Entity._on_turn_started` runs at the owning entity's turn start. Stats it consumes:

- `action_points` → `restore_to_full()`
- `deallocation_points` → `restore_to_full()`
- `xp` → `replenish(int(xp_per_turn.value))`
- `wound_heal_per_turn` → `skill_points.heal(int(value))` (wounded → current)
- (also, for each node owned by the entity) `SkillNode.refill()` — node combat HP back to max

`wound_heal_per_turn` defaults to 1. Tuning lever: raise to recover faster from forced deallocs; drop to make wound damage stickier.

## Stat IDs

Run to list all current stat IDs:
```
grep -h "^id = " stats_system/defs/*.tres | sort
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
| `dexterity` | `range` | INCREASE | `DEX × 1.0` (LinearFormula scale=1) — at DEX=30 → +30% |
| `strength` | `blade_size` | ADD_BASE | `floor(STR / 10.0)` |

## Gotchas

- **DerivedModifierDef must not be shared across entities.** Always `.duplicate(true)` before `add_modifier()`. Intrinsics are safe — `apply_intrinsics()` auto-duplicates them.
- **Pool modifiers target the pool id, not a `_max` suffix.** `"health"` targets the health cap. `"health_max"` doesn't exist.
- **`max` is a GDScript built-in.** Never name a property or variable `max` on PoolStat or its subclasses — it shadows `max()` in all subclass methods. Use `.value` for the cap. (Same risk for `range`, `min`, etc. — the `range` stat property is OK because nothing in `StatBoard`'s methods calls the global `range()`.)
- **StatBoard field name must match the stat's `id` string.** `get_stat(id)` calls `Object.get(id)` — renaming either without the other silently breaks lookup.

## Visualizer (editor plugin)

`addons/stat_board_visualizer/` — Inspector button on any `StatBoard` .tres mounts it in the "StatBoard" bottom panel. Runtime F3 overlay is `ui/stat_board_overlay/`.

- **Add modifiers** — toolbar `+` button OR drag a stat's port to another stat's port (presets as Linear `source × scale`). Disk-backed boards persist via `ResourceSaver`; runtime boards mutate in memory only.
- **Expression formula inputs are auto-derived.** `ExpressionFormula.detect_inputs(text, candidates)` uses word-boundary regex; the dialog live-validates while typing.
