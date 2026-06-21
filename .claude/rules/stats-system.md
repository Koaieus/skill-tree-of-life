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

### Def hierarchy

`PoolStatDef` is abstract — concrete pools pick one of two subclasses, never the base directly. PoolStat stays agnostic to which subclass it holds; behaviour is delegated through two virtuals on the base:

- `on_pool_filled(stat, excess)` — fires when `current` crosses up to the cap. `excess` is the amount of the inbound replenish that was clipped by the cap-clamp.
- `on_max_increased(stat, delta)` — fires when the modifier pipeline raises the cap (cap *decreases* are handled by PoolStat: current is clamped).

| Def class | When to use | Adds |
|---|---|---|
| `StandardPoolStatDef` | Fixed-cap pool (HP, mana, AP, DP, SP, movement) | `heal_on_max_increase: bool` — if true, `on_max_increased` bumps current by delta so the relative fill stays the same |
| `GrowablePoolStatDef` | Gauge that grows when filled (XP today; any future "fill-and-level" pool) | `growth_flat: float`, `growth_factor: float`, `post_grow_mode: PostGrowMode` |

`PostGrowMode` (Growable only): `KEEP` (current parks at old cap, new headroom = delta) · `RESET` (current → min_value, new cap empty) · `OVERFLOW` (level-up consumes `old_max` worth of replenish; new level starts at `min_value + excess` — cascades naturally through multiple level-ups if the inbound replenish was huge). XP uses `OVERFLOW`.

Growth math: `new_max = stat._coerce(old_max * growth_factor + growth_flat)` — coercion is via the stat's `value_type`, so int pools snap and float pools don't. Growth writes `base_value` directly (bypassing the modifier path) so a growable pool's level-up does NOT trigger StandardPoolStatDef's `heal_on_max_increase` — same deliberate pattern as `SkillPointStat.claim()`. BOOL `value_type` is hidden from the inspector via `_validate_property` on `PoolStatDef` — meaningless for a cap.

`skill_points` is `SkillPointStat` (PoolStat subclass). Max is the canonical PoolStat value (base + modifier pipeline). `current` is the spendable bucket; `wounded` and `staked` are two extra book-keeping buckets sitting *inside* max. **`used` is derived**: `max - current - wounded - staked` — SP locked into currently-allocated nodes. Operations:

| Method | Effect | Mints? |
|---|---|---|
| `spend(n)` | current -= n (used derives +n) | no |
| `refund(n)` | current += n (used derives -n) | no |
| `wound(n)` | wounded += n (used derives -n) | no |
| `heal(n)` | wounded -= n; current += n | no |
| `stake(n)` | current -= n; staked += n | no |
| `extract(n)` | staked -= n; current += n | no |
| **`claim(n)`** | `base_value += n` — max grows, current unchanged, the new SP lands in `used`. Equivalent to "grant(n) then spend(n)" collapsed atomically. Use for force_allocate / scripted setup. | **yes** |
| **`grant(n)`** | `base_value += n; current += n` — mints free SP (level-up). | **yes** |

Modifiers on `skill_points` behave like modifiers on any other PoolStat — they bump max via the pipeline, and `heal_on_max_increase=true` on the def causes modifier-driven max changes to also bump current. `claim()` bypasses the modifier path (writes base_value directly) so heal_on_max_increase does NOT fire — that's exactly what distinguishes it from grant.

Scene-authored ownership (e.g. dev_sandbox `owned_by = NodePath(...)`) doesn't go through `force_allocate`, so `AllocationSystem.register_scene_authored_ownership()` walks the graph at GameRoot._ready and claims for each pre-owned node. Procgen content runs later and claims via force_allocate — no double-count.

## Turn-start upkeep

`Entity._on_turn_started` runs at the owning entity's turn start. Stats it consumes:

- `action_points` → `restore_to_full()`
- `deallocation_points` → `restore_to_full()`
- `xp` → `replenish(int(xp_per_turn.value))`
- `wound_heal_per_turn` → `skill_points.heal(int(value))` (wounded → current)
- (also, for each node owned by the entity) `SkillNode.refill()` — node combat HP back to max

`wound_heal_per_turn` defaults to 1. Tuning lever: raise to recover faster from forced deallocs; drop to make wound damage stickier.

After the entity's own upkeep, `Entity._on_turn_started` calls `core_class.on_turn_started(self)` so the wired class can run its own per-turn effects (mana regen for casters, rage decay for berserkers, etc.). Default hook is a no-op.

## Class identity modifiers (CoreClass)

Per-entity class bonuses live on `Entity.core_class: CoreClass` (`entity/core/`), NOT on the stat board's intrinsic list or as an Entity-level modifier array (the old `Entity.core_modifiers` field was removed). `Entity._ready` calls `core_class.apply(self)` once, which `duplicate(true)`s every entry in `CoreClass.modifiers` before installing — same `.tres` is safe across many entities. `BalancedCore` is the +10 STR/DEX/INT baseline against which other classes are tuned; create new classes by extending `CoreClass` and authoring a `.tres`. Procgen sandboxes wire the class via `GameRoot.spawn_entity(..., core_class)`; hand-authored scenes set it on the Entity node directly.

## Stat IDs

Run to list all current stat IDs:
```
grep -h "^id = " stats_system/defs/*.tres | sort
```

## Intrinsic scaling (entity/default_entity_board.tres)

These are `StatModifier` sub-resources with a `formula`, wired as `intrinsic_modifiers` on the default board — all entities get them. Keep them inline in the board .tres (not separate files). Effective contribution = `modifier.value × formula.compute(board)`; with `value = 1` the formula reads through. **Update this table when adding or changing one.**

| Input stat | Target stat | Op | value | formula |
|---|---|---|---|---|
| `perception` | `vision_range` | INCREASE | 2 | LinearFormula(perception) — at PER=3 → +6% |
| `intelligence` | `mana` | ADD_BASE | 1 | `floor(intelligence / 10.0)` |
| `intelligence` | `mana_per_turn` | ADD_BASE | 1 | `floor(log(max(1e-5, intelligence))/log(10.0))` |
| `wisdom` | `xp_per_turn` | ADD_BASE | 1 | `floor(log(max(1e-5, wisdom))/log(10.0))` |
| `dexterity` | `sensor_range` | ADD_BASE | 1 | `floor(dexterity / 10.0)` |
| `dexterity` | `range` | INCREASE | 1 | LinearFormula(dexterity) — at DEX=30 → +30% |
| `strength` | `blade_size` | ADD_BASE | 1 | `floor(strength / 10.0)` |

## Gotchas

- **Formula-driven modifiers must not be shared across entities.** Each carries mutable `_board` / `_bound_sources` binding state. Always `.duplicate(true)` before `add_modifier()`. Intrinsics are safe — `apply_intrinsics()` duplicates every entry.
- **Pool modifiers target the pool id, not a `_max` suffix.** `"health"` targets the health cap. `"health_max"` doesn't exist.
- **`max` is a GDScript built-in.** Never name a property or variable `max` on PoolStat or its subclasses — it shadows `max()` in all subclass methods. Use `.value` for the cap. (Same risk for `range`, `min`, etc. — the `range` stat property is OK because nothing in `StatBoard`'s methods calls the global `range()`.)
- **StatBoard field name must match the stat's `id` string.** `get_stat(id)` calls `Object.get(id)` — renaming either without the other silently breaks lookup.

## Visualizer (editor plugin)

`addons/stat_board_visualizer/` — Inspector button on any `StatBoard` .tres mounts it in the "StatBoard" bottom panel. Runtime F3 overlay is `ui/stat_board_overlay/`.

- **Add modifiers** — toolbar `+` button OR drag a stat's port to another stat's port (presets as Linear `source × scale`). Disk-backed boards persist via `ResourceSaver`; runtime boards mutate in memory only.
- **Expression formula inputs are auto-derived.** `ExpressionFormula.detect_inputs(text, candidates)` uses word-boundary regex; the dialog live-validates while typing.
