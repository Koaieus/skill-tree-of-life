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
- `move_core` → after `entity.core_location = target`

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
| `Keystone` | `effects` + implicit `StatEffect` wrapping `modifiers` | `AllocationSystem`, keyed by carrier node |
| `SkillNodeAddon` | `effects` | same, via `SkillNode.get_node_effects()` |
| `SkillNode` | `effects` | same |

`Keystone` is now actually wired — its docstring advertised "runtime wiring into
AllocationSystem is a follow-up" since it was written. Its `keystone` reference was
also promoted from `set_meta("keystone", …)` to a real `SkillNode.keystone` export.

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

## Deferred

- **Auras** (phase 2) — `RangeFinder.gather` + `AuraEffect` + `DistanceScale`.
  Blocked on a real bug: `Mitigation.apply` reads the *entity* board, so node-local
  `armor` never reaches the damage formula (`bunker_addon` has never worked).
- **LifeLine** — "kept alive despite being islanded" overrides the islanding rule.
  It needs a **query hook with a return value** inside
  `nodes_islanded_by_removing_set` / the cascade, not a fire-and-forget notification
  and not a modifier grant. Different hook shape; its own issue.
- **Presentation** — icon + `get_description()` rendering in the HUD.
