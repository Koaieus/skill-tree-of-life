---
description: Stat system quick-reference — pipeline, stat IDs (grep), intrinsic scaling, gotchas
paths:
  - "stats_system/**"
  - "entity/default_entity_board.tres"
---

# Stat system reference

**Keep current.** Any change to the stat system — new stat, new formula type, modified pipeline, new pool or modifier class, new intrinsic scaling rule — must be followed by updating this rule.

## Modifier pipeline

`(base + ADD_BASE) × (1 + INCREASE/100) × MULTIPLY + ADD_BONUS`

- **SET** short-circuits everything; highest `priority` wins, last-in breaks ties at equal priority. **Convention:** class-identity SETs (e.g. `pacifist_core.tres` SETting `movement_points`/`deallocation_points` to 0) author `priority = 100` so the anchor sits above any node/keystone/addon SET (those default to 0). Keep class SETs at this tier; leave node content below it.
- **INCREASE** sums additively (PoE-style). Five +20% = ×2.0, NOT (1.2)⁵.

## Local stats (per-node overrides)

`SkillNode.node_board` is a sparse `StatBoard` — all fields start null, created only when a node-local modifier targets them (via `_ensure_local_stat(id)`) or when the node is allocated (combat health pool). No `LocalStat` class — the merge happens directly: `StatBoard.get_stat(id)` may differ per board, and combined reads use `ModifierBins.compute()` with bins from both the entity and node board.

Read side: `SkillNode.get_local_value(id)` returns the combined value without allocating — entity stat pass-through when the node board has no stat for that id. Modifier target side: `_ensure_local_stat(id)` creates (if needed) and returns the stat on `node_board`; addons route their `local_modifiers` here.

**SET tiebreak:** highest priority wins; at equal priority **last source listed wins**. The combined read orders `[entity.bins, node.bins]` so a node-local SET beats an entity SET at the same priority.

For entity-absent fallback: `get_local_value(id)` uses `StatRegistry.get_def(id).default_value` when neither board carries the stat.

### Node combat health

The node's health is a `PoolStat` on `node_board` with id `"node_combat_health"` (`StandardPoolStatDef`, `heal_on_max_increase = true`). On allocation, `base_value` is synced from the owning entity's `node_health` ScalarStat baseline and re-syncs on `value_changed`. `current` tracks damage; `deplete()` / `restore_to_full()` replace the old `current_hp` float. See `skill_node/skill_node.gd:_refresh_hp_binding`.

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

`deallocation_points` and `movement_points` are `SurplusPoolStat` (PoolStat subclass, #152/#156). Unlike SkillPointStat's bins which sit *inside* max, its one extra bin — `surplus: int` — sits **outside** the cap:

```
available() == roundi(current) + surplus     # may exceed .value
```

Surplus is a **transient budget boost** (extra DP/MP for one turn). It's deliberately outside two systems that would otherwise stomp it:
- **`restore_to_full()`** only moves `current` against the cap, so a turn-start REFILL leaves surplus untouched (that's the whole point — a turn-start cap-modifier boost would arrive *after* the refill that fills it).
- **The modifier pipeline** never consults it — no `heal_on_max_increase`, and crucially it survives a `SET`-short-circuit. A `SET cap = 0` pool with nonzero surplus is a legal, meaningful state (an entity whose entire DP/MP budget is bought with unspent AP); a cap-modifier design can't represent it.

Contract: **overwritten each turn, never accumulated** — write it with `set_surplus(n)` (never an `add_surplus`, which would let an idle entity compound it). `deplete()` draws **surplus-first** (burn-it-or-lose-it: the boost is spent on travel or wasted; ordinary budget survives an idle turn). Cap changes never clamp surplus.

**Gates and budgets must read `available()`, not `.current`.** `PoolStat.available()` (base) returns `roundi(current)`; `SurplusPoolStat` overrides it to add the bin. So `AllocationSystem.can_deallocate` / `can_move_core` / `_movement_budget`, `HighlightController`, and `PlayerInputController` all read `available()` and honour surplus polymorphically without knowing the subclass. A gate reading `.current` would grant cells the player can't spend.

**Negative caps are undefined — don't reach for them.** `PoolStat.set_current` does `clamp(v, _min_value(), cap)`; with `cap = -1` the range inverts and `clamp` returns the cap, so `current` lands at `-1` (below floor) and `depleted` fires on *every* write, including every turn-start `restore_to_full()`. Harmless for DP/MP (nothing listens), fatal for `health` (`depleted` → `die()`). Express a penalty as a debt bin with real semantics, or clamp caps at zero — a real `min_value` change is its own issue.

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

**Fractional rates accumulate, they don't truncate.** `SkillPointStat.wound_heal_progress` (0..1, runtime-only) banks `wound_heal_per_turn` every turn upkeep; once it crosses 1.0 *and* `wounded > 0` it heals 1 SP and drains by 1.0. A rate below 1 (e.g. 0.5 — two turns per healed SP) would silently heal nothing forever under a naive `int(rate)` per-turn call, which is what this replaced. While `wounded == 0` the progress holds at a capped 1.0 instead of wrapping — nothing to spend it on yet — so it reads "full" until the entity is wounded again, at which point the *very next* turn upkeep immediately heals and drains it. `wound_heal_progress_changed(progress)` is what `turn_resources_panel.gd` binds its sliver to; the label showing the rate itself is always visible (not gated on `wounded > 0`) since the rate is a stat a player wants to see even unwounded.

`health` is `NONE` (the core does not auto-heal yet — a future "1/turn" core regen would be `ADD` with a `health_per_turn` companion, or a `CoreClass.on_turn_started` hook for class-specific healing).

### Turn-*end*: unused-AP → DP/MP surplus (#152)

`Entity._on_turn_ended` transfers each unused action point into next turn's `deallocation_points`/`movement_points` **surplus**, scaled by the **`ap_transfer_rate`** ScalarStat (default 2 — see "Turn Budget" board field). `boost = roundi(unused_ap × rate)`; the product is rounded so a future fractional/DEX-scaled rate doesn't truncate. Because `ap_transfer_rate` is an ordinary board stat, **class identity tunes it with no bespoke mechanism** — a Pacifist raises it, a Berserker drops it to 0 (see `PacifistCore`). `Entity.DEFAULT_AP_TRANSFER_RATE` is the fallback only for sparse/test boards that carry no such stat. This lives at turn *end*, not start, because unused AP is only known then; turn-start REFILL then leaves the surplus untouched (it's outside the cap). `set_surplus` **overwrites**, so a turn ending with all AP spent writes 0 and self-clears the prior boost. See the `SurplusPoolStat` note under "Pool stats".

### Then: node refill + class hook

- (for each node owned by the entity) `SkillNode.refill()` — node combat HP back to max.
- `core_class.on_turn_started(self)` — the wired class runs its own per-turn effects (caster mana flourishes, rage decay, etc.). Default hook is a no-op.

## Composite (bundled) modifiers (#183)

`CompositeStatModifier extends StatModifier` bundles several child modifiers
into **one atom** for the storage / authoring / loot layer, while flattening
into its children wherever a modifier is actually **applied** or fully
**listed**. Motivating case: a class-identity buff/debuff pair balanced only as
a unit — authored as one `CoreClass.modifiers` entry, it loots all-or-nothing so
a collector can't cherry-pick the buff (see `ninja_core.tres`'s `mod_budget_pack`
= +2 DP / −1 SP).

**The whole feature is one virtual: `StatModifier.flatten() -> Array[StatModifier]`.**
A leaf returns `[self]`; the composite returns its children (recursively). Two
worlds:

- **Keep whole (storage/authoring/loot):** `CoreClass.modifiers`,
  `core_location.modifiers`, loot `candidates` — a composite is ONE entry / ONE
  pick-N-from-M candidate.
- **Flatten (application/full-listing):** two apply seams flatten and route
  each leaf — `StatBoard.add_modifier`/`remove_modifier` (entity board:
  allocation, addons' `entity_modifiers`, effects, intrinsics, loot grant) and
  `SkillNode.add_local_modifier`/`remove_local_modifier` (node board: addons'
  `local_modifiers`, node-scoped effect grants). So **every** application path
  gets bundle support for free. Display / per-mod-floater sites that list every
  leaf flatten too: `SkillNodeTooltip._add_modifier_label`, `LootPicker._make_card`
  (one card per candidate, body lists the leaves), `SkillDustAddon._grant_mods`
  and `AllocationVfx` (the #70 floaters — **one per leaf**, honest about each
  stat gained). `StatModifier.flatten_all(mods)` is the list-level helper for
  the per-entry iterators.

**INERT container:** the composite's own `stat_id`/`operation`/`value`/`formula`/
`priority` are vestigial (hidden via `_validate_property`); only leaves bind and
apply. Because add_modifier flattens, a child's `emit_changed()` reaches its Stat
through the normal wiring — the container never proxies signals. `duplicate(true)`
deep-copies the `children` array (verified — Godot recurses into an exported
Array of Resources), so no `duplicate()` override is needed and the per-element
dup discipline for formula-bound mods holds for a bundle too.

**Gotcha:** iterating a typed `Array[StatModifier]` and testing `m is
CompositeStatModifier` is a parse error (the element type resolves by script
*path*, the class by *class_name*, and the analyzer won't narrow between them).
Copy into an untyped `var mods: Array` first. See `test_composite_stat_modifier.gd`.

## Effect-granted modifiers (#4)

`Effect`s grant modifiers through `EffectContext.grant(mod, target)`, which
`.duplicate(true)`s once and records the handle in the `EffectInstance` ledger.
`target` is null (entity board) or a `SkillNode` (its `node_board`).

**Provenance is the retained handle, not a field.** `StatModifier` still has no
`source`, and `ModifierBinding.Kind` stays dormant — the ledger makes `revoke_all`
exact without changing the schema. Don't add a source field for this.

**Never store runtime state on an `Effect`** — a single `.tres` is shared across
every entity carrying it. State goes on the per-grant `EffectInstance`.

Entity-scoped node modifiers now route through `SkillNode.add_entity_modifier` /
`apply_entity_modifiers_to(board)` rather than callers hand-rolling
`modifiers.append(m)` + `board.add_modifier(m)`. Node-scoped ones go through
`add_local_modifier` / `remove_local_modifier`. See `docs/domain/effect-system.md`.

## Class identity modifiers (CoreClass)

Per-entity class bonuses live on `Entity.core_class: CoreClass` (`entity/core/`), NOT on the stat board's intrinsic list or as an Entity-level modifier array (the old `Entity.core_modifiers` field was removed). `Entity._ready` calls `core_class.apply(self)` once, which `duplicate(true)`s every entry in `CoreClass.modifiers` before installing — same `.tres` is safe across many entities. `BalancedCore` is the +10 STR/DEX/INT baseline against which other classes are tuned; create new classes by extending `CoreClass` and authoring a `.tres`. Procgen sandboxes wire the class via `GameRoot.spawn_entity(..., core_class)`; hand-authored scenes set it on the Entity node directly.

## Stat IDs

Run to list all current stat IDs:
```
grep -h "^id = " stats_system/defs/*.tres | sort
```

## `level` is a plain ScalarStat, written imperatively (#200)

`level` lives on the board as an ordinary `ScalarStat` (id `level`, INT, default 1) — **not** a bespoke derived/read-only class and **not** a `fill_count` on `PoolStat`. It exists so level-scaling formula modifiers (`+level × 1 STR`, #194) can `board.get_stat(&"level")` and auto-recalc: `Entity._on_xp_replenished` does `stat_board.level.base_value += 1`, and `base_value`'s setter emits `value_changed`, which walks the same reactive path as any formula source (PER→vision, etc.). No new mechanism.

Consequences to respect:
- **`Entity.level` is a proxy** onto `stat_board.level.value` (getter) / `.base_value` (setter), with a `1` fallback for sparse/test boards that carry no `level` stat. There's no separate `int` counter — the stat is the single store. Don't reintroduce one.
- Level stays **moddable** like every other stat (a `+2 level` modifier is legal and lifts effective level). That's deliberate — don't special-case it read-only.
- The level-up path writes `base_value` (not effective value) so it never double-counts any level modifiers.

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

> **KNOWN BUG (fix scheduled in #4 phase 2): node-local `armor` never reaches this
> formula.** `SkillNode.take_damage` passes `owned_by.stat_board` — the *entity*
> board — so any `armor` on `node_board` is ignored. `bunker_addon.tscn`
> (`local_modifiers = [armor ADD_BONUS +5]`) has therefore never done anything,
> while `combat_readout_card.gd` *displays* the node-local value via
> `get_local_value`. Tooltip says +5, combat disagrees; no error either way.
> Fix is `Mitigation.apply(raw, node)` reading `node.get_local_value(&"armor")` and
> `get_local_value(&"min_damage_taken")`. Every armor aura depends on it.
>
> Note the floor is a floor, not a cap: negative armor pushes damage *above* raw,
> but only once `raw - armor > min_damage_taken` (default 3). At `raw=1, armor=-1`
> you take 3, not 2.

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

## Display contract — RETIRED in #120

**`ui/stats_panel.gd` was deleted in #118** (HudRoot cutover); it was the only consumer of `StatDef`'s `display_type`/`display_group`/`display_order`/`parent_stat_id` and the `DisplayType` enum. #120 formally **retired all four fields plus the enum** — stripped from `stat_def.gd` and migrated out of every `stats_system/defs/*.tres`. `StatDef` now carries only `id`, `display_name`, `description`, `value_type`, `default_value`, `tint_color`.

HudRoot's cards (AttributesPanel, CombatReadout, TurnResourcesPanel) hardcode which specific stat ids they bind. So **adding a stat means dropping a `.tres` in `stats_system/defs/` and wiring it into whichever HudRoot card should show it** (directly, by stat id — see e.g. `attributes_panel.gd`/`combat_readout.gd`). There is no generic metadata-driven panel; don't reintroduce `display_*` fields expecting one to pick them up. If a future generic consumer (debug stat-dump, modding inspector) returns, it defines its own presentation metadata then.

## Visualizer (editor plugin)

`addons/stat_board_visualizer/` — Inspector button on any `StatBoard` .tres mounts it in the "StatBoard" bottom panel. Runtime F3 overlay is `ui/stat_board_overlay/`.

- **Add modifiers** — toolbar `+` button OR drag a stat's port to another stat's port (presets as Linear `source × scale`). Disk-backed boards persist via `ResourceSaver`; runtime boards mutate in memory only.
- **Expression formula inputs are auto-derived.** `ExpressionFormula.detect_inputs(text, candidates)` uses word-boundary regex; the dialog live-validates while typing.
