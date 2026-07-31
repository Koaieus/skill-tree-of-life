---
description: Stat system quick-reference — pipeline, stat IDs (grep), intrinsic scaling, gotchas
paths:
  - "stats_system/**"
  - "entity/default_entity_board.tres"
  - "docs/domain/stat-ui-visibility.md"
---

# Stat system reference

> **Breadcrumb:** For which stat appears where in the HUD (or doesn't), see
> `docs/domain/stat-ui-visibility.md`.

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

### Node regen stats (`node_healing` / `node_healing_ramp`, D-9 #270)

Two **node-local** scalars read through `get_local_value` — so a single node can be tuned to regen faster than its owner's baseline. `node_healing` is the flat per-turn heal; `node_healing_ramp` is the extra granted per consecutive undamaged turn.

The stack counter itself is **runtime state on `SkillNode` (`regen_stacks`), not a stat** — same reasoning as node HP: it's per-node combat bookkeeping that resets constantly and nothing should be able to modify it. **There is deliberately no cap stat**; the ramp self-limits by stopping at max HP and resetting. Don't add one.

Turn-start refill-to-full is **gone** (D-9) — damage persists across turns. `SkillNode.refill()` survives for the allocation path only, and the resulting dealloc/realloc full-heal is an **accepted interaction, not a bug** (it costs DP/MP and needs topology permitting the dealloc without islanding). See `docs/domain/node-hp.md`.

### CoreClass auras (D-10, #270)

`CoreClass.aura` holds a `CoreAura` resource; `HealAura` is the first concrete one. `value_at_hop(h) = base × (1 − h/range)`, clamped at 0, with **both `base` and `range` authored — never derived**. Deriving range from base would make a strong aura automatically a wide one, and covered-node count grows ~quadratically in radius; bounding coverage is the whole point, since an aura blanketing most of an entity's territory out-heals the chip damage driving the forced-dealloc death clock.

- **Aura parameters live on the resource, NOT the stat board.** Don't add `aura_heal_base`/`aura_heal_range` as stats.
- **Hop distance is measured over the OWNED subgraph** (`entity.navigator`) via `RangeFinder.gather`, never the global navigator and never `in_range` in a loop — see `.claude/rules/graph.md`.
- The aura heals **through** the damage gate but **grants no ramp**; it's additive outside the ramp term: `total = (node_healing + stacks × ramp) + aura_at_hop`.
- The resource is a **channel, not a payload** — armor/damage auras are equally valid. Don't hardcode "aura == healing" into its shape.

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

### `replenished` fires in REVERSE chronological order across a cascade — `value_changed` doesn't

A single `replenish(huge_amount)` that crosses multiple levels recurses: `set_current` → `on_pool_filled` (grows `base_value`, which fires `value_changed` immediately) → recursive `set_current` for the overflow → ... → only once the recursion bottoms out does control unwind and each frame's `replenished.emit()` fire. So for a 2-level cascade, the **deepest (final, highest) level's `replenished` fires first**, and the first/lowest level's fires last — backwards from the order the levels were actually reached in.

`value_changed` doesn't have this problem: it fires at the point `base_value` is written, which is *before* the recursive call for that frame — so across the cascade it fires in true ascending (chronological) order.

**How to apply:** anything that needs to replay a multi-level cascade in order (e.g. a UI sequencer chaining "fill to old cap → grow → fill to new content" once per level) must build its segment list from `value_changed` snapshots, not from counting/ordering `replenished` calls. Verified by tracing `pool_stat.gd:set_current` against `growable_pool_stat_def.gd:on_pool_filled`; `test_overflow_huge_replenish_cascades_through_levels` (test/unit/test_growable_pool_stat_def.gd) confirms `replenished` fires twice for a 2-level cascade but doesn't assert order — a gap worth closing if a consumer ever depends on it.

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
| Top-up by a rate | `ADD` | `current += <rate stat>.value` (clamped) | `mana` (+`mana_per_turn`), `xp` (+`xp_per_turn`), `health` (+`core_healing`) |
| Bespoke | `CUSTOM` | `PoolStat._custom_turn_upkeep(board)` override | `skill_points` (heals `wound_heal_per_turn` wounds) |

`PoolStatDef.per_turn_mode` (base-class field, default `NONE`) declares the verb. `StatBoard.apply_per_turn_upkeep()` enumerates every `PoolStat` field by introspection (`get_pool_stats()`) and calls `pool.run_turn_upkeep(self)`; the per-pool behaviour lives on `PoolStat`, the board is just the sweep. So **a new pool opts into upkeep by setting `per_turn_mode` on its def, not by editing `_on_turn_started`** (that was the footgun: `movement_points` was never restored and `mana_per_turn` was never consumed because nobody remembered to wire them). ADD resolves its rate stat through `PoolStatDef.resolved_per_turn_stat_id()` and `push_warning`s if it's missing.

**ADD's rate stat is `<id>_per_turn` by convention, overridable by name (#277).** `per_turn_stat_id` on `PoolStatDef` (empty = the convention) exists because `health`'s rate is **`core_healing`**, named for the mechanic rather than for the pool it fills — D-25 names it, and #268 registers a balance invariant using that name, so renaming it to `health_per_turn` to fit the convention would break the traceability the design is written against. Set the override only for that reason; a rate stat with no independent identity should keep the convention. A `CoreClass.on_turn_started` hook is *not* the place for this — pool upkeep stays declarative (see the footgun above).

**`CUSTOM` and the def-vs-stat hook split:** `wound_heal` isn't a pool top-up — it transfers SP from the `wounded` reservation back to `current` (a bin move inside `SkillPointStat`, conditional on `wounded > 0`). It can't be REFILL/ADD, so `skill_points` is `CUSTOM` and `SkillPointStat._custom_turn_upkeep()` does the `heal()`. Note this hook lives on the **stat** (`PoolStat`/`SkillPointStat`), whereas `on_pool_filled` / `on_max_increased` live on the **def** (`PoolStatDef` subclasses): cap-shape behaviour varies by def archetype → on the def; behaviour that touches the stat's *own extra state* (the SP bins) → on the stat. **Behaviour lives where its data lives.** A stray `REFILL`/`ADD` on `skill_points` would corrupt the `wounded`/`staked` bins — `test_per_turn_upkeep` guards the CUSTOM path.

`wound_heal_per_turn` defaults to 1. Tuning lever: raise to recover faster from forced deallocs; drop to make wound damage stickier.

**Fractional rates accumulate, they don't truncate.** `SkillPointStat.wound_heal_progress` (0..1, runtime-only) banks `wound_heal_per_turn` every turn upkeep; once it crosses 1.0 *and* `wounded > 0` it heals 1 SP and drains by 1.0. A rate below 1 (e.g. 0.5 — two turns per healed SP) would silently heal nothing forever under a naive `int(rate)` per-turn call, which is what this replaced. While `wounded == 0` the progress holds at a capped 1.0 instead of wrapping — nothing to spend it on yet — so it reads "full" until the entity is wounded again, at which point the *very next* turn upkeep immediately heals and drains it. `wound_heal_progress_changed(progress)` is what `turn_resources_panel.gd` binds its sliver to; the label showing the rate itself is always visible (not gated on `wounded > 0`) since the rate is a stat a player wants to see even unwounded.

`health` is `ADD` with `core_healing` as its rate (D-25, #277): an **integer** heal, placeholder `1`/turn, **ungated and unramped**. No damage gate — a gate only exists to make a ramp meaningful, and a ramping out-of-combat heal would reward exactly the camping D-10's forced-dealloc cascade is engineered to punish. (Node regen *does* ramp and *is* gated — D-9 — because a held node recovering is territory you are defending. Don't unify the two.) Integer rather than a sub-1 sliver because the gauges already render an "incoming next turn" band: `hero_sigil_card.gd` binds `health` ← `core_healing` the same way it binds mana (and the way `xp_track.gd` binds `xp` ← `xp_per_turn` since XP moved out of the card in #320), so the UI cost was zero. `test_core_healing.gd` pins the no-gate and no-ramp contracts.

**#268 invariant, named not implemented:** if `core_healing >= dealloc_damage × nodes_lost_per_turn`, camping is viable again and D-10's structural guarantee is silently undone. `1` is the break-even against a 1-node-per-turn chip — a placeholder per D-13, not a blessed value.

`initiative` is the remaining `NONE` pool (tick-driven by TurnManager, not the sweep).

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
  leaf flatten too: `GrantedModifiersRoot._rebuild_rows`, `LootPicker._make_card`
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

Per-entity class bonuses live on `Entity.core_class: CoreClass` (`entity/core/`), NOT on the stat board's intrinsic list or as an Entity-level modifier array (the old `Entity.core_modifiers` field was removed). `Entity._ready` calls `core_class.apply(self)` once, which `duplicate(true)`s every entry in `CoreClass.modifiers` before installing — same `.tres` is safe across many entities. `BalancedCore` is the +10 STR/DEX/INT baseline (plus +1 each per level — see "Per-level class bonuses" below) against which other classes are tuned; create new classes by extending `CoreClass` and authoring a `.tres`. Procgen sandboxes wire the class via `GameRoot.spawn_entity(..., core_class)`; hand-authored scenes set it on the Entity node directly.

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

## Per-level class bonuses ride the ordinary `modifiers` array (#194)

There is **no `level_up_modifiers` field and no per-level-up mutation.** A "+1 STR per level" class bonus is one ordinary `StatModifier` in `CoreClass.modifiers` with `value = 1.0` (the coefficient) and `formula = level_scaling.tres`. Level-up writes `level.base_value`, that emits `value_changed`, the bound modifier recomputes — the reactive chain is the one every other formula uses. Adding a fresh `+1 STR` modifier on each level-up is the anti-pattern: N modifier instances, N subscriptions, and cleanup on death.

**The curve is shared and lives in one file:** `stats_system/formulas/level_scaling.tres` is `ExpressionFormula("level - 1")`. Every class references that same file, so retuning the level curve is a one-file edit. It's `level - 1`, not `level`, so a level-1 entity sits exactly on its authored baseline (Balanced reads +10, not +11) and each level-up adds the coefficient.

**Keep the formula in its own `.tres` — never inline it into a class.** `Resource.duplicate(true)` **preserves the identity of a file-backed sub-resource and copies an inline one** (verified empirically under Godot 4.4, both directions). That asymmetry is load-bearing here: `CoreClass.apply()` deep-duplicates every modifier, and the duplicate must keep pointing at the *shared* curve. Inlining the formula into `balanced_core.tres` would silently fork it per entity — the class would still work, but the shared-tuning property (and any identity check against the resource) would quietly die with no error. It also explains why `composite_stat_modifier.gd` can claim `duplicate(true)` deep-copies its `children`: those are inline.

Sharing one formula instance across entities is safe because `StatFormula` is stateless — all binding state (`_board`, `_bound_sources`) lives on the *modifier*, which does get duplicated. The "MUST NOT be shared" warning in `stat_modifier.gd` is about the modifier, not its formula.

**Query level bonuses with `StatModifier.scales_with(&"level")`**, not a marker field or resource identity. The formula's declared `get_input_ids()` already answer "does this scale with level?", the answer survives duplication, and it stays true for a class that authors its own `ExpressionFormula("(level - 1) * dexterity")` instead of the shared curve. It asks every leaf via `flatten()`, so a composite reports true when any child scales. Two call sites use it with opposite signs — the #199 HUD listing (include) and `LootSystem._is_lootable` (exclude). Route any third through the same predicate.

**Level-scaled mods are not lootable.** They vanish with the entity like the rest of the core set, but the loot draw excludes them: a looted copy keeps the shared formula and would rebind to the *looter's* level, granting a scaling relic nobody designed. Lootable relics that scale with the holder's level are a real feature — if wanted, design it deliberately, don't let it fall out of the draw.

## Intrinsic scaling (entity/default_entity_board.tres)

These are `StatModifier` sub-resources with a `formula`, wired as `intrinsic_modifiers` on the default board — all entities get them. Keep them inline in the board .tres (not separate files). Effective contribution = `modifier.value × formula.compute(board)`; with `value = 1` the formula reads through. **Update this table when adding or changing one.**

| Input stat | Target stat | Op | value | formula |
|---|---|---|---|---|
| `perception` | `vision_range` | INCREASE | 2 | LinearFormula(perception) — at PER=3 → +6% |
| `intelligence` | `mana` | ADD_BASE | 1 | RatioFormula(intelligence, 10) |
| `intelligence` | `mana_per_turn` | ADD_BASE | 1 | `floor(log(max(1e-5, intelligence))/log(10.0))` |
| `wisdom` | `xp_per_turn` | ADD_BASE | 1 | RatioFormula(wisdom, **2**) |
| `dexterity` | `sensor_range` | ADD_BASE | 1 | RatioFormula(dexterity, 10) |
| `dexterity` | `range` | INCREASE | 1 | LinearFormula(dexterity) — at DEX=30 → +30% |
| `dexterity` | `ranged_damage` | ADD_BASE | 1 | RatioFormula(dexterity, 10) |
| `intelligence` | `spell_range` | ADD_BASE | 1 | LinearFormula(intelligence) |
| `strength` | `blade_size` | ADD_BASE | 1 | RatioFormula(strength, **20**) |
| `strength` | `blade_damage` | ADD_BASE | 1 | RatioFormula(strength, 10) |
| `constitution` | `node_health` | ADD_BASE | 1 | LinearFormula(constitution) — TBD (#268): the rate **is** this coefficient, +1 HP per CON |
| `constitution` + `core_health_scaling` | `health` | ADD_BASE | 1 | `core_health_scaling * constitution` (D-21/D-26, #276) — the rate is the **stat**, not the coefficient (see below) |
| `level` | `constitution` | ADD_BASE | 1 | `level_scaling.tres` (`level - 1`) — TBD (#268), +1 CON per level |

### Formula classes — pick the narrowest one (#289)

| Class | Shape | Describes itself as |
|---|---|---|
| `RatioFormula(source, divisor)` | `floor(source / divisor)` | "per 20 STR" (generated) |
| `LinearFormula(source)` | `source` | "per PER" (generated) |
| `ExpressionFormula(text, inputs)` | anything | authored `per_phrase`, or nothing |

**`floor(stat / N)` must be a `RatioFormula`, never an `ExpressionFormula`.**
Six intrinsics were hand-written expressions until #289; the divisor lived only inside a
string, so the prose describing it drifted in four separate places at once (the panel said
`/10` while blade size computed `/20`; this very table said `decade of WIS` while XP regen
computed `/2`). With `divisor` a typed field, `describe_per()` renders the same number
`compute()` divides by — they cannot disagree.

**Every formula owes a one-line `per_phrase`.** `StatModifier.format()` appends it —
"+1 Blade Size **per 20 STR**" — and renders the modifier's `value` (the coefficient)
rather than the effective value, because the clause now carries the variable part. Ratio
and Linear generate the phrase; an `ExpressionFormula` must author one on the resource
(`"×10 INT"`, `"CON × core scaling"`, `"level after the 1st"`). It is deliberately **not
multiline** — a formula-bound modifier renders as a single-Label glass slab (`ModSlabRow`)
in a hover tooltip, and prose would blow the line budget. Nothing may derive the phrase by
parsing the expression string. `test_formula_descriptions.gd` fails on an undescribed
formula reachable from the shipped boards.

`AttributeRules` (Attributes Panel hover) now **discovers** these lines by scanning
`intrinsic_modifiers` for `scales_with(attr_id)` — it holds no rule text of its own, so
this table is documentation, not a second source of truth.

**Put a rate in `value`, not in the formula string.** Most expression-formula intrinsics above bake their rate into the expression (`floor(strength / 10.0)`) and leave `value` at its 1.0 default. That still works — the knob exists on every modifier — but it splits the rate across two places, and turning `value` up on a `floor(X/10)` formula scales the already-*stepped* output rather than the rate. CON→`node_health` deliberately does it the other way: a `LinearFormula` passthrough of `constitution` with the rate as the modifier's `value`, so #268 retunes it in exactly one field. Prefer that shape for new intrinsics; `mod_per_to_vision` (2.0 × PER) and every `level_scaling` class bonus already follow it.

**CON → `health` puts its rate in a *stat*, not in `value` (D-26, #276).** `health = 10 + core_health_scaling × CON`: the flat 10 is `pool_health`'s `base_value` (baked for now — D-26 defers making it a stat to #279's authoring problem), and the coefficient is `core_health_scaling`, an ordinary board scalar defaulting to `1.0`. It's a stat rather than a modifier `value` because a **CoreClass must be able to move it** — `core_health_scaling` sizes the pool, `dealloc_damage` sizes the chip, and `nodes_lost_before_death = health / dealloc_damage` is where class identity lives (Balanced 119÷1, Glass 119÷3, Bulwark 119÷0.5). Both are plain board stats, so a class tunes either with an ordinary modifier — **no genesis/class-param mechanism is needed or wanted here.** Consequence for the formula: it's an `ExpressionFormula` with **both** ids in `inputs`, or changing the class knob won't rebind.

`core_health_scaling` is **entity-scope only** — as a node-local stat it means nothing (D-26 surfaced this; #287 is the open decision). Don't add it to a procgen pool.

**The D-21 ratchet lives in `StandardPoolStatDef.grant_max_increase_delta`.** Allocating CON raises the `health` cap *and* hands you the delta as current HP, so a player can cycle territory to heal. That is **knowingly exploitable and accepted** (D-21) — the graph *is* the mechanics, and DP is not free, so the ratchet is bounded. D-26 requires the grant to stay one named, greppable method rather than being inlined into an allocation path, so the toggle is findable when it's revisited; `health.tres` carries `heal_on_max_increase = true` deliberately and says so in its `description`. The *infinite* version is closed at the other end: `deallocation_points.tres` sets `heal_on_max_increase = false`, so a node granting `+1 max DP` raises the maximum **without** granting a spendable point. Both halves are pinned by `test_entity_health_scaling.gd` — don't "tidy" either flag. The recorded-but-not-adopted alternative (voluntary dealloc subtracts the delta and is illegal if lethal; forced dealloc reduces max only) is the first thing to reach for if the ratchet misbehaves.

**CON (D-11/D-12/D-14, #269) — the level→CON grant lives on the board, and only there (user decision, 2026-07-24).** D-15 originally named `BalancedCore` as its home, mirroring `+1 STR/DEX/INT per level`. It was settled the other way: the board intrinsic means **every** entity's durability scales with level regardless of core class, which is the asymmetry #269 existed to fix. **`BalancedCore` therefore contributes the +10 CON *base* grant (#271) but must NOT get a per-level CON entry in its `level_scaling` modifiers** — that would double-count against the board intrinsic. CON is the one attribute whose level channel is board-side; STR/DEX/INT remain class-side.

`constitution.tres`'s `default_value` is **0**, not 10 like the other four attributes — deliberately, so a level-1 *bare* board's `node_health` baseline stays at flat 10. The +10 baseline arrives as BalancedCore's class grant (#271), matching how the other attributes get theirs.

CON does **not** get an intrinsic targeting `armor` or `min_damage_taken` — D-11 decision 3 is load-bearing (a prior draft that let CON drive `armor` produced a permanent dead zone against uninvested attackers). `test_constitution.gd` guards this explicitly.

**Procgen home:** `procgen/pools/constitution.tres` is CON's own `StatPack` (PRIMARY role, `archetype_stat = &"constitution"`, mirrors `strength.tres`'s ADD_BASE/INCREASE/MULTIPLY tier structure targeting the `constitution` stat itself — not `node_health` directly). Its `off_phase_op_weights` (`{ADD_BASE:0.5, INCREASE:0.3, MULTIPLY:0.1, ADD_BONUS:0.3}`) is the **explicit, named exception** D-12 asks for: less severe than `wisdom.tres`/`perception.tres`'s suppression (`0.2/0.05/0.0/0.05`), so a non-CON node's off-archetype roll into CON content fades less than into WIS/PER content. The **other half** of "less severe for CON/defensive" is the `TierPool.Role.DEFENSIVE` pools (`node_health` INCREASE, `armor` ADD_BASE) — they bypass `off_phase_op_weights` *and* the cost cap entirely, drawn every time regardless of the node's `primary_stat`. Since **#299 those live in `constitution.tres` too**; the old `defensive.tres` is deleted.

**`constitution.tres` is therefore a mixed pack** — the only one that serves two draw phases. That works because `ModifierPoolSet.flatten_for_phase` filters on **per-`TierPool`** `role` / `archetype_stat`; the pack-level `archetype_stat` is inert documentation, and the pack-level `off_phase_op_weights` is consulted only in the `&"off"` branch, which by construction never sees DEFENSIVE pools. Moving the pools between packs was provably a no-op on generated content. `test_constitution.gd::test_constitution_pack_serves_both_primary_and_defensive_phases` pins the invariant — if someone ever makes pack-level `archetype_stat` gate the flatten, that test is the tripwire.

**#299 also dropped `node_health` ADD_BASE entirely.** Base `node_health` is `10 + CON` and `BalancedCore` grants +10 CON at level 1, so a flat `+2–4` draw was numerically identical to the `+10–20%` INCREASE draw at level 1 and decayed from there. Only the percent channel survives, re-ranged to `+5–15%` (floor is 5% because `node_health` is INT-typed: at an L1 base of 20, a `+2%` roll is +0.4 HP and rounds away).

**HUD gap (#228, partially closed by #289):** `AttributeRules` no longer has a per-attribute `match`, so CON's hover lines (`node_health`, `health`) now render. `ui/hud/attributes_panel/attributes_panel.gd` still hardcodes the 5-attribute row/radar list, so CON has no row to hover from — that half remains open under #228.

## Damage mitigation

`Mitigation.apply(raw, defender_board)` (`attack/formulas/mitigation.gd`) runs inside `SkillNode.take_damage` before HP soak. Formula:

```
final = max(min_damage_taken, raw.amount - armor)
```

- `TRUE`-typed damage bypasses everything and lands raw.
- `raw.amount <= 0` returns 0 — the floor only triggers on a real hit.
- `armor` scalar (default 0) and `min_damage_taken` scalar (default 3) are both standard board stats — modifiers / intrinsics apply normally. Defensive cores (e.g. Bulwark) can drive `min_damage_taken` below 0, allowing damage to *heal* nodes if the underflow is large enough.
- Rare procgen modifier `-1 min_damage_taken` is a high-tier exotic roll.

**Both stats are read node-locally.** `Mitigation.apply(raw, defender)` takes the
`SkillNode` and reads `defender.get_local_value(&"armor")` /
`get_local_value(&"min_damage_taken")`, which merges the node's `node_board` bins
with the owner's board through one `ModifierBins.compute`. So a node-scoped
defensive modifier — `bunker_addon.tscn`'s `armor ADD_BONUS +5`, or a core-class
aura — actually reaches the damage formula.

> This was broken until **be477f5**: `take_damage` passed `owned_by.stat_board`,
> the *entity* board, so every node-local `armor` was silently discarded while
> `combat_readout_card.gd` happily displayed it. Tooltip said +5, combat
> disagreed, no error either way. Recorded because the failure mode — a
> node-local stat that displays correctly and computes wrong — is easy to
> reintroduce in any new formula that takes a board instead of a node.

Note the floor is a floor, not a cap: negative armor pushes damage *above* raw,
but only once `raw - armor > min_damage_taken` (default 3). At `raw=1, armor=-1`
you take 3, not 2.

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
