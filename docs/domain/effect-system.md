# Effect system (#4)

Persistent, hook-driven behaviour attached to an `Entity`. Effects are how a
core class, a keystone, or an addon does something that doesn't reduce to a flat
stat modifier — auras, per-turn rules, on-kill triggers.

## `Effect` vs `OnHitEffect`

Two different things that both end in "Effect". They are siblings, not a hierarchy.

| | `Effect` (`effects/effect.gd`) | `OnHitEffect` (`attack/spell/on_hit/`) |
|---|---|---|
| Lifetime | granted → lives → revoked | fires once, per spell hit |
| State | grant ledger on `EffectInstance` | none |
| Dispatch | `Entity.dispatch(hook)` | `SpellResolver` per landed node |

## Composition, not a subclass zoo

There is no `TurnStartEffect` / `BattleStartEffect` split — an effect can't be
both, so a subclass-per-trigger design is uncomposable. **Triggers are methods.**
The composite is an `Array[Effect]` on the carrier, which the inspector edits
natively; that is also why no `CompositeEffect` exists.

`Serpent` is the proof: two `AuraEffect`s side by side, one hop-metric buff and
one euclidean-metric penalty.

## Hooks are declared, not inherited

`Effect` defines **no** `_on_*` world/combat hooks. A subclass implements only
what it cares about, so `has_method()` is an exact test of "does this effect
care". `Entity.grant_effect` buckets by hook once, making `dispatch` O(interested)
rather than O(all effects).

Legal names live in `Effect.HOOKS`. The cost of the `has_method` approach is that
a typo would silently never fire, so `test_effect.gd::test_every_declared_hook_name_is_legal`
walks every `Effect` subclass and asserts each `_on_*` it defines is legal. That
lint carries its own vacuity guard — if the subclass walk stops resolving, it
fails rather than passing on an empty set.

`_on_granted` / `_on_revoked` are the exception: defined on the base, always called.

| Hook | Fired from |
|---|---|
| `_on_granted` / `_on_revoked` | `Entity.grant_effect` / `revoke_effect` |
| `_on_turn_start` / `_on_turn_end` | `Entity._on_turn_started` / `_on_turn_ended` |
| `_on_node_allocated` / `_on_node_deallocated` | `AllocationSystem`, all four allocate/deallocate paths |
| `_on_core_moved` | `AllocationSystem.move_core` |
| `_on_level_up` | `Entity._on_xp_replenished` |
| `_on_entity_dying` | `Entity.die()`, before the bus phases |
| `_on_attack_launched`, `_on_node_damaged`, `_on_killing_blow` | *(phase 1: declared, not yet dispatched)* |

**There is no `_on_battle_start`.** The issue asked for one, but no battle concept
exists: `BattleSystem` is a per-attack plan resolver with no encounter boundary,
no "current enemy", no combat-entered state. The attack-shaped hooks above replace
it — each maps onto a real emit site.

## Dispatch lives on `Entity`, not in a central system

Signals are split across three places (the `Events` autoload, per-system locals on
TurnManager/AllocationSystem/BattleSystem, and per-entity `Entity.leveled_up`). A
central `EffectSystem` subscriber would have to re-bind all three, plus every
entity as it spawns.

Instead systems **call the entity directly at the mutation site they already
touch**, mirroring how `AllocationSystem` already calls `entity.navigator.mirror_add(node)`.

**Ordering is load-bearing.** Dispatch *after* the world is coherent, or an aura
recomputes against a stale mirror:

- `allocate` / `force_allocate` → after `mirror_add(node)`
- `deallocate` / `force_deallocate` → after `mirror_remove(node)` and `owned_by = null`

**`_on_core_moved` is dispatched from the `Entity.core_location` setter, not from
`AllocationSystem.move_core`.** `move_core` is only one caller. `GameRoot.spawn_entity`
assigns `core_location` *after* `_ready` has already granted the core class's
effects — so an aura's `_on_granted` runs against a null core and an empty mirror,
and without a setter dispatch nothing ever re-fires it. The aura then buffs nothing,
forever, while every hand-ordered test passes. The setter is the one point that
catches spawn, scene-export deserialization, and `move_core` alike.

There are **four** ownership-claim paths, and all four must grant node effects:
`allocate`, `force_allocate`, the death/attack `force_deallocate` inverse, and
`register_scene_authored_ownership` (dev_sandbox `owned_by` NodePaths), which
bypasses `force_allocate` entirely.

## Provenance is the retained handle, not a field

`StatModifier` has no `source` field and removal is by object identity.
`ModifierBinding.Kind` exists but is deliberately dormant. We don't promote it:
`EffectInstance` keeps a **grant ledger** of the exact duplicated `StatModifier`
instances it applied, paired with where each landed (entity board, or a node's
`node_board`). That makes `revoke_all` exact without touching `StatModifier`'s schema.

Grants go through `EffectContext`, which does the `.duplicate(true)` once — so the
"formula-driven modifiers carry mutable per-entity binding state and must never be
shared" gotcha is impossible to get wrong from an effect.

**Grants are mid-life, not boundary-only.** An effect may `ctx.grant()` / `ctx.revoke()`
from any hook, not just `_on_granted`. `AuraEffect` does exactly this as its buffed
set shifts.

## Effects are shared resources — never store runtime state on them

One `.tres` may sit on every entity of a class. A `var _buffed := {}` member on an
`AuraEffect` would have every Ninja silently clobbering every other Ninja's buffed
set, surfacing only once two entities of the same class coexist. This is the same
trap `CoreClass` has (its docstring warns about it); it resurfaces one level down.

State belongs on the per-grant `EffectInstance`. An aura reads its current buffed
set back from the ledger (`ctx.handles_for(node)`) rather than caching its own dict.

## Carriers gain `effects[]` alongside `modifiers`

The pure-stat path already works and authors cleanly, so `Effect` is additive:

| Carrier | Field | Granted by |
|---|---|---|
| `CoreClass` | `effects` | `CoreClass.apply()`, from `Entity._ready` |
| `Keystone` | `effects` | `AllocationSystem`, keyed by carrier node |
| `SkillNodeAddon` | `effects` | same, via `SkillNode.get_node_effects()` |
| `SkillNode` | `effects` | same |

`Keystone` is now actually wired — its docstring advertised "runtime wiring into
AllocationSystem is a follow-up" since it was written. Its `keystone` reference was
also promoted from `set_meta("keystone", …)` to a real `SkillNode.keystone` export.

`Keystone` used to carry its own `modifiers` array, wrapped lazily into an implicit
`StatEffect`, and a `StatKeystone` subclass existed as the "just a stat bundle"
concrete pick. Both are gone (#149): the fields were field-for-field `Effect`'s, so
a keystone's stat payload is now simply a `StatEffect` in its `effects` array, and
`Keystone` is pure identity + payload.

Node-borne effects register against the **owning entity** with `source_node` set,
and `revoke_effects_from(node)` strips exactly those on deallocation. An unowned
node's effects are dormant.

## Modifier plumbing is centralized on `SkillNode`

One public API, used by addons, effects, and `AllocationSystem` alike:

- `add_entity_modifier(m)` / `remove_entity_modifier(m)` — entity-scoped: joins
  `node.modifiers` and mirrors onto the owner's board if allocated.
- `apply_entity_modifiers_to(board)` / `remove_entity_modifiers_from(board)` — the
  ownership transitions, driven by `AllocationSystem`.
- `add_local_modifier(m)` / `remove_local_modifier(m)` — node-scoped, lands on
  `node_board`. Read back with `get_local_value(id)`, which merges node + entity
  bins through one `ModifierBins.compute` without allocating.

Previously `_on_addon_added` and `AllocationSystem.allocate` each hand-rolled the
"append to `modifiers` + push to the owner's board" dance.

## Auras

`AuraEffect` has three orthogonal knobs, and keeping them separate is the whole design:

| Knob | Question | `null` means |
|---|---|---|
| `reach: RangeFinder` | *which* nodes | flood the whole scope |
| `metric: DistanceMetric` | *how far* each is | reuse the distances `reach` reported |
| `distance_scale: DistanceScale` | multiplier at that distance | flat |

Several designed auras answer "which" and "how far" with **different metrics** —
the Serpent's penalty applies to every node the core can reach (topological) but
scales by euclidean distance (spatial). Collapsing that into one
`EuclideanRangeFinder` forces `max_distance` past the map diagonal and makes the
bound a trap: too small a value silently lets distant nodes escape the *penalty*.
`reach: null` removes the sentinel entirely.

**Sign lives on the modifier, shape lives on the scale.** A negative `value` makes
a debuff aura; a rising scale grows its magnitude with distance. They compose
freely, which is why `DistanceScale` is not called "falloff" — the return is an
unbounded scalar, not an attenuation. (`Gradient` was also rejected: Godot ships
one, and `Edge.gd` holds one.)

| Class | `reach` | `metric` | `distance_scale` |
|---|---|---|---|
| Bulwark | `EuclideanRangeFinder` / `HopRangeFinder` | inherited | `FlatScale` |
| Halo | `HopRangeFinder(shell+1)` | inherited | `ShellScale` |
| Ninja | `HopRangeFinder(2)` | inherited | `LinearScale` (falling, `strength` buff) |
| Serpent A | `null` | `HopMetric` | `ProportionalScale` (positive mods) |
| Serpent B | `null` | `EuclideanMetric` | `ProportionalScale` (negative mods) |

Ninja shipped bounded rather than the unbounded-debuff shape this table used to
show (that shape lives on as `test_aura_effect.gd`'s generic direction-agnostic
`ProportionalScale` demo, not as the class) — the design doc calls for an
*intense, very-short-range buff*, and an unbounded `ProportionalScale` can't
express "bounded": pairing it with a bounded reach is the trap the scale's own
docstring warns about. `NinjaCore`/`ninja_core.tres` and `SerpentCore`/
`serpent_core.tres` (#39) are the reference implementations for this table now.

Serpent's two components land on the same stat as `ADD_BONUS` and sum through one
`ModifierBins.compute` — `Array[Effect]` *is* the composite.

`recompute` is a **full rebuild** (`revoke_all`, then re-grant), not an incremental
diff: an owned subgraph is tens of nodes, it runs on allocation events rather than
per frame, `revoke_all` also purges ledger rows whose node a cascade freed, and a
rebuild cannot drift out of sync with the buffed set the way a diff can.

Reach queries go through `RangeFinder.gather`, never `in_range` in a loop — see
`.claude/rules/graph.md`.

## Deferred

- **LifeLine** — "kept alive despite being islanded" overrides the islanding rule.
  It needs a **query hook with a return value** inside
  `nodes_islanded_by_removing_set` / the cascade, not a fire-and-forget notification
  and not a modifier grant. Different hook shape; its own issue. Design sketch
  (including the broader "status tags" grant channel this implies) now lives in
  [status-tags.md](../design/status-tags.md) (it moved to `docs/design/` while
  unimplemented; it moves back here once shipped).
- **Presentation** — icon + `get_description()` rendering in the HUD.
- **Node-local effect bin** — a coherent-but-empty sibling to `node_board`. The
  stat side is symmetric (entity `stat_board` ↔ per-node `node_board`, combined on
  read); the effect side is not, and deliberately so. **Effects are push, stats are
  pull**: a `node_board` hosts anywhere because "combine on read" needs no
  dispatcher, but an effect instance's home is decided by *who fires its hooks*, and
  every hook today (`_on_turn_start`, `_on_node_allocated`, `_on_core_moved`,
  `_on_level_up`, `_on_killing_blow`) is an **entity/subgraph** event. So even a
  node-granted effect is *hosted* at the entity (instance keyed by `source_node`).
  Note the two axes are orthogonal: an aura may *radiate from* its carrier node
  (geometry — the `source_node ?? core_location` origin rule, #240) while still being
  *dispatched by* the entity (host). **Trigger to fill this cell:** the first effect
  authored to react to a node's *own* lifecycle (`skill_node_depleted`, addon
  stamped, node damaged) and mutate *only* node-local state. That effect belongs
  hosted on the `SkillNode`, which then grows its own `_on_*` dispatch + a per-node
  `EffectInstance` bin. Until such content exists, don't build the node-as-dispatch-host
  machinery — it's speculative double-plumbing.

## Known limits — file an issue to extend

This is the boundary of what the effect system can express **today**. Hitting one
of these is the signal to file (or revisit) an issue, not to work around it locally:

| You want… | Status | Extend via |
|---|---|---|
| An effect that reacts to a **node's own** lifecycle and mutates only that node | Not supported (all dispatch is entity-scoped) | Node-local effect bin — see Deferred above |
| A **non-numeric marker** on a node/entity (`poisoned`, `has_lifeline`, `marked`) | Not supported (only grant target is `StatModifier`) | Status tags — [#240](../design/status-tags.md) |
| An aura that **radiates from its carrier node**, not core | Not supported (`recompute` hardcodes `core_location`) | Origin rule `source_node ?? core_location` — [#240](../design/status-tags.md) |
| A hook that **returns a value** to change *whether* something happens (LifeLine veto) | Not supported (hooks are fire-and-forget `void`) | Query hook — LifeLine, Deferred above |
| An effect on an **unallocated** node (map/environment hazard) | Not supported (node effects are dormant until owned) | A distinct `NodeHazardEffect` feature — no issue yet |
| A spell/tag grant that **survives its granting node** on death | Handled *outside* the ledger (`SpellBook` innate/permanent add) | Spellbook looting — [#204](https://github.com/Koaieus/skill-tree-of-life/issues/204) |
