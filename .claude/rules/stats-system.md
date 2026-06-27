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

The base also carries `per_turn_mode: PerTurnMode {NONE, REFILL, ADD, CUSTOM}` — how the pool replenishes at turn start (`CUSTOM` dispatches to a `PoolStat` virtual). See "Turn-start upkeep" below. Default `NONE`.

| Def class | When to use | Adds |
|---|---|---|
| `StandardPoolStatDef` | Fixed-cap pool (HP, mana, AP, DP, SP, movement) | `heal_on_max_increase: bool` — if true, `on_max_increased` bumps current by delta so the relative fill stays the same |
| `GrowablePoolStatDef` | Gauge that grows when filled (XP today; any future "fill-and-level" pool) | `growth_flat: float`, `growth_factor: float`, `post_grow_mode: PostGrowMode` |
| `CyclicPoolStatDef` | Recurring threshold that resets on fill, carrying overshoot forward (`initiative` today) | nothing — `on_pool_filled` just does `set_current(min + excess)` (no growth) |

`CyclicPoolStatDef` is the cap-as-recurring-threshold archetype: filling does NOT grow the cap and does NOT leave `current` parked at the cap — it restarts the cycle at `min + excess`, so the "deduct one cap's worth on cross" is implicit and an entity that overshot more keeps that lead. It's Growable's `OVERFLOW` post-grow path minus the growth (Growable can't be reused — its `on_pool_filled` bails when the cap delta is 0). The `replenished` signal still fires at the crossing (before the carry-reset), which is how `initiative` marks an entity ready — see `.claude/rules/turn-manager.md`. `per_turn_mode = NONE` (it's tick-driven by TurnManager, not the turn-start sweep).

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

`Entity._on_turn_started` runs at the owning entity's turn start. It does, in order: **pool replenishment** (one declarative sweep), **wound healing** (bespoke), **node HP refill**, then the **class hook**.

### Pool replenishment is declarative (`per_turn_mode`)

"Per turn" is **three different verbs**, not one — don't conflate them:

| Verb | `PerTurnMode` | Operation | Pools |
|---|---|---|---|
| Reset-to-cap | `REFILL` | `restore_to_full()` | `action_points`, `deallocation_points`, `movement_points` |
| Top-up by a rate | `ADD` | `current += <id>_per_turn.value` (clamped) | `mana` (+`mana_per_turn`), `xp` (+`xp_per_turn`) |
| Bespoke | `CUSTOM` | `PoolStat._custom_turn_upkeep(board)` override | `skill_points` (heals `wound_heal_per_turn` wounds) |

`PoolStatDef.per_turn_mode` (base-class field, default `NONE`) declares the verb. `StatBoard.apply_per_turn_upkeep()` enumerates every `PoolStat` field by introspection (`get_pool_stats()`) and calls `pool.run_turn_upkeep(self)`; the per-pool behaviour lives on `PoolStat`, the board is just the sweep. So **a new pool opts into upkeep by setting `per_turn_mode` on its def, not by editing `_on_turn_started`** (that was the footgun: `movement_points` was never restored and `mana_per_turn` was never consumed because nobody remembered to wire them). ADD derives the companion id as `&"%s_per_turn"` and `push_warning`s if it's missing.

**`CUSTOM` and the def-vs-stat hook split:** `wound_heal` isn't a pool top-up — it transfers SP from the `wounded` reservation back to `current` (a bin move inside `SkillPointStat`, conditional on `wounded > 0`). It can't be REFILL/ADD, so `skill_points` is `CUSTOM` and `SkillPointStat._custom_turn_upkeep()` does the `heal()`. Note this hook lives on the **stat** (`PoolStat`/`SkillPointStat`), whereas `on_pool_filled` / `on_max_increased` live on the **def** (`PoolStatDef` subclasses): cap-shape behaviour varies by def archetype → on the def; behaviour that touches the stat's *own extra state* (the SP bins) → on the stat. **Behaviour lives where its data lives.** A stray `REFILL`/`ADD` on `skill_points` would corrupt the `wounded`/`staked` bins — `test_per_turn_upkeep` guards the CUSTOM path.

`wound_heal_per_turn` defaults to 1. Tuning lever: raise to recover faster from forced deallocs; drop to make wound damage stickier.

`health` is `NONE` (the core does not auto-heal yet — a future "1/turn" core regen would be `ADD` with a `health_per_turn` companion, or a `CoreClass.on_turn_started` hook for class-specific healing).

### Then: node refill + class hook

- (for each node owned by the entity) `SkillNode.refill()` — node combat HP back to max.
- `core_class.on_turn_started(self)` — the wired class runs its own per-turn effects (caster mana flourishes, rage decay, etc.). Default hook is a no-op.

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
| `strength` | `blade_damage` | ADD_BASE | 1 | `floor(strength / 10.0)` |

## Damage mitigation

`Mitigation.apply(raw, defender_board)` (`attack/formulas/mitigation.gd`) runs inside `SkillNode.take_damage` before HP soak. Formula:

```
final = max(min_damage_taken, raw.amount - armor)
```

- `TRUE`-typed damage bypasses everything and lands raw.
- `raw.amount <= 0` returns 0 — the floor only triggers on a real hit.
- `armor` scalar (default 0) and `min_damage_taken` scalar (default 3) are both standard board stats — modifiers / intrinsics apply normally. Defensive cores (e.g. Bulwark) can drive `min_damage_taken` below 0, allowing damage to *heal* nodes if the underflow is large enough.
- Rare procgen modifier `-1 min_damage_taken` is a high-tier exotic roll.

## Forced-dealloc damage

When a node's combat HP hits 0, `BattleSystem._on_node_depleted` runs the cascade (impact + islanded set). Each cascaded node costs the defender two things, neither going through `Mitigation`:

- `skill_points.wound(1)` — moves 1 SP from `used` → `wounded`. Currency exchange; SP isn't refunded, it's reserved until `wound_heal_per_turn` ticks it back. Knob: hardcoded 1 (one node lost = one wound, tight coupling on purpose).
- `health.deplete(dealloc_damage.value)` — chip damage off the entity HP pool. Default 1. **Tuning lever** — a fragile-core class can raise it (e.g. Glass Cannon = 3) to make every cascaded node hurt more. Skips `Mitigation.apply` deliberately — wounds and dealloc damage are explicitly "bypass armor" by design (read the user-facing framing: it's a currency exchange, not an attack landing).

Both are emitted per cascaded node in the same loop, so a 5-node cascade with `dealloc_damage = 2` deals 5 wounds + 10 HP, ignoring armor.

## Gotchas

- **Formula-driven modifiers must not be shared across entities.** Each carries mutable `_board` / `_bound_sources` binding state. Always `.duplicate(true)` before `add_modifier()`. Intrinsics are safe — `apply_intrinsics()` duplicates every entry.
- **Pool modifiers target the pool id, not a `_max` suffix.** `"health"` targets the health cap. `"health_max"` doesn't exist.
- **`max` is a GDScript built-in.** Never name a property or variable `max` on PoolStat or its subclasses — it shadows `max()` in all subclass methods. Use `.value` for the cap. (Same risk for `range`, `min`, etc. — the `range` stat property is OK because nothing in `StatBoard`'s methods calls the global `range()`.)
- **StatBoard field name must match the stat's `id` string.** `get_stat(id)` calls `Object.get(id)` — renaming either without the other silently breaks lookup.

## Display contract (StatsPanel + future tooltips)

`StatDef.display_type: {BASIC, BAR, PROGRESS, INLINE, HIDDEN}` picks the widget; `display_order` sorts the column; `tint_color` colours the bar fill. `ui/stats_panel.gd` enumerates `StatRegistry.get_all_defs()`, drops HIDDEN, drops any id the board lacks, sorts by `display_order`, and dispatches:

- `BASIC` → `Label` (default for scalars)
- `PROGRESS` → `ProgressBar` (`max_value = stat.value`, `value = pool.current`) with a centred `"Name: current/max"` label child. Default for every `PoolStat` def.
- `INLINE` → dimmed sub-row rendered immediately after the row named by `StatDef.parent_stat_id`. Name label prefixed with `"+ "`. Use for per-turn stats and other derivatives. Ignored `display_group` — tab is inherited from parent.
- `BAR` → reserved; falls through to `BASIC`.
- `HIDDEN` → omitted from the panel entirely.

**Tab taxonomy (3 tabs):**
- `overview` — pools (health, mana, SP, DP, AP, movement, XP) + base attributes (STR, DEX, INT, WIS, PER). Per-turn stats (mana_per_turn, xp_per_turn, wound_heal_per_turn) appear as INLINE under their parent.
- `combat` — blade_size, blade_damage, armor, dealloc_damage, min_damage_taken, range, vision_range, sensor_range, initiative_speed.
- `magic` — spell_range and future magic-specific stats.

Adding a stat means dropping a .tres in `stats_system/defs/` with `display_type` + `display_order` + `display_group` set. For INLINE, set `parent_stat_id` instead of `display_group`. The panel picks it up on next board bind. The escape hatch for non-stock rendering (e.g. a sloshing mana ball) is to add an `@export var widget_scene: PackedScene` to `StatDef` and dispatch on it before the enum — not implemented yet, but that's the slot.

## Visualizer (editor plugin)

`addons/stat_board_visualizer/` — Inspector button on any `StatBoard` .tres mounts it in the "StatBoard" bottom panel. Runtime F3 overlay is `ui/stat_board_overlay/`.

- **Add modifiers** — toolbar `+` button OR drag a stat's port to another stat's port (presets as Linear `source × scale`). Disk-backed boards persist via `ResourceSaver`; runtime boards mutate in memory only.
- **Expression formula inputs are auto-derived.** `ExpressionFormula.detect_inputs(text, candidates)` uses word-boundary regex; the dialog live-validates while typing.
