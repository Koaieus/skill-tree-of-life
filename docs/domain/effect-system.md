# Effect system (#4)

Persistent, hook-driven behaviour attached to an `Entity`. **Stat math — a
formula included — is a `StatModifier`; an `Effect` is for behaviour that needs
a lifecycle hook** (grant/revoke-time work, turn start, on kill, core moved, an
aura re-evaluated as distances change). A core class, a landmark, or an addon
reaches for one only for that. Stacked, ticking debuffs and damage-over-time are
not `Effect`s: see [status-effects.md](status-effects.md).

## `Effect` vs `OnHitEffect`

Two different things that both end in "Effect". They are siblings, not a hierarchy.

| | `Effect` (`effects/effect.gd`) | `OnHitEffect` (`attack/spell/on_hit/`) |
|---|---|---|
| Lifetime | granted → lives → revoked | fires once, per landing |
| State | grant ledger on `EffectInstance` | none |
| Dispatch | `Entity.dispatch(hook)` | each mode's resolver, per `HitLanding` |

**The payload seam (ADR 0044):** authoring a new on-hit thing = an
`OnHitEffect` on the carrier's `on_hit_effects`. It reads a mode-agnostic
`HitLanding` (attacker, source, origin, read_node, target, structural key, `paired`, the
`hits` sink), so the same effect works on a spell, an arrow and a blade. An
effect that needs spell context extends `SpellOnHitEffect` (narrows to
`LandingContext`). A status rides `HitLanding.paired`, and
`HitInstance.paired` gates it (`rider_gated`): no landed paired hit, no status.
A spell's status is not authored here but emitted by its `SpellAffinity` list via `Infusion.riders` (ADR 0047).

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
| `_on_turn_start` / `_on_turn_end` | `Entity.begin_turn` / `finish_turn` |
| `_on_node_allocated` / `_on_node_deallocated` | `AllocationSystem`, all four allocate/deallocate paths |
| `_on_core_moved` | `AllocationSystem.move_core` |
| `_on_level_up` | `Entity._on_xp_replenished` |
| `_on_entity_dying` | `Entity.die()`, before the bus phases |
| `_on_attack_launched` | `BattleSystem`, after costs are deducted and the plan is still live |
| `_on_node_damaged` | `SkillNode` damage path, to the owner, with the post-mitigation amount |
| `_on_killing_blow` | `LootSystem`, on the killer, pre-strip (the corpse still owns its nodes) |

**There is no `_on_battle_start`.** `BattleSystem` is a per-attack plan resolver with no encounter boundary, no "current enemy", no combat-entered state; the attack-shaped hooks above each map onto a real emit site.

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

## The context acts through a SLICE, not an Entity (#520)

`EffectContext.combat` is an `EntityCombat`, and `EffectContext.world` is the
`CombatWorld` it belongs to. Everything that used to reach `entity.stat_board` /
`entity.navigator` / `node.add_local_modifier` now reaches the slice instead, so
**the identical `Effect` code recomputes against a shadow board when handed a
shadow slice** — a node grant routes through `world.combat_for(node)` and lands on
that node's slice in the same world. There is no preview branch anywhere in
`effect_context.gd`: the world is the parameter. `ctx.entity` still answers with
the real `Entity`, but for **identity only** (attitude, display); an effect that
wants to *change* something goes through `ctx.combat`, or a shadow recompute would
write to the live entity. `EffectInstance.clone_for(combat)` is the shadow's
stand-in for a live grant row — the ledger rows are copied, the handles inside them
stay the live `StatModifier` instances, which is what lets a shadow revoke a grant
it never issued (`StatBoard._localized` translates the handle). See
[attack-timeline.md](attack-timeline.md).

## Effects are shared resources — never store runtime state on them

One `.tres` may sit on every entity of a class. A `var _buffed := {}` member on an
`AuraEffect` would have every Ninja silently clobbering every other Ninja's buffed
set, surfacing only once two entities of the same class coexist. This is the same
trap `CoreClass` has (its docstring warns about it); it resurfaces one level down.

State belongs on the per-grant `EffectInstance`. An aura reads its current buffed
set back from the ledger (`ctx.handles_for(node)`) rather than caching its own dict.

## Carriers gain `effects[]` alongside `modifiers`

The pure-stat path already works and authors cleanly, so `Effect` is additive:

| Carrier | Field | Granted by | Its stat bundle goes in |
|---|---|---|---|
| `CoreClass` | `effects` | `CoreClass.apply()`, from `Entity._ready` | `modifiers` |
| `SkillNode` | `effects` | `AllocationSystem`, keyed by carrier node | `modifiers` |
| `SkillNodeAddon` | `effects` | same, via `SkillNode.get_node_effects()` | `entity_modifiers` / `local_modifiers` |

Every authored carrier has its own modifier array, so a pure stat bundle never
rides in its `effects` (check the addon *scenes*, not only the script: bunker,
fortification, spike ring, toxin and watchtower all author modifiers and no
effect). Only a runtime `Entity.grant_effect` from a source with no carrier
of its own has nowhere else to put one.

A landmark ("keystone") is a hand-authored inherited scene of
`skill_node/keystone/keystone_skill_node.tscn` whose stat payload is plain
`SkillNode.modifiers` SubResources of the `.tscn`. Owner call, 2026-09-24: a pure
stat bundle belongs in the node's `modifiers` array, not wrapped in a
`StatEffect` — wrapped, the tooltip read an empty aura and "(no modifiers)".
`SkillNode.effects` is for a landmark that does something behavioural; its
payload is a live reference, read at every allocation, one shared resource safe
across entities.

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


## Auras

`AuraEffect` has four orthogonal knobs, and keeping them separate is the whole design:

| Knob | Question | `null` / default means |
|---|---|---|
| `reach: RangeFinder` | *which* nodes | flood the whole scope |
| `metric: DistanceMetric` | *how far* each is | reuse the distances `reach` reported |
| `distance_scale: DistanceScale` | *what value* at that distance | flat (the authored value) |
| `discard: Discard` | *is it worth granting* | `NON_POSITIVE` |

Several designed auras answer "which" and "how far" with **different metrics** —
the Serpent's penalty applies to every node the core can reach (topological) but
scales by euclidean distance (spatial). Collapsing that into one
`EuclideanRangeFinder` forces `max_distance` past the map diagonal and makes the
bound a trap: too small a value silently lets distant nodes escape the *penalty*.
`reach: null` removes the sentinel entirely.

**Sign lives on the modifier, shape lives on the scale.** A negative `value` makes
a debuff aura; a rising scale grows its magnitude with distance. They compose
freely, which is why `DistanceScale` is not called "falloff" — the return is an
unbounded value, not an attenuation. (`Gradient` was also rejected: Godot ships
one, and `graph/edge.gd` holds one.)

### The scale returns the VALUE, not a multiplier (#900)

`scale(d, max, v)` takes the authored number as its third argument and returns
what to grant. The library classes are now spellings of that — `FlatScale` is
`v`, `LinearScale` is `v * (1 - d / max)`, `ProportionalScale` is `v * d` — and
`ExpressionScale` lets an author write the formula directly:

```
"5 - d"               # 5 at the core, 4, 3, 2, 1 — an ABSOLUTE ladder
"v * (1 - d / max)"   # LinearScale
```

The absolute ladder is what the multiplier contract could never express, and it
is why the change was made: `LinearScale` ties the decay rate to the reach, so
its rim ring is always 0 and `max_hops N` silently buys an (N-1)-hop aura.

Two traps, both documented on the classes themselves:

- **`max` is not a legal `Expression` identifier.** Godot's lexer reserves it
  for the built-in `max()`, so a formula naming it fails at *parse* with
  "Expected `(`". `ExpressionScale` keeps the authored spelling and rewrites
  `max` → `__max` on a word boundary (`maxf`/`maxi` are untouched).
- **For a `MULTIPLY` or `SET` leaf the result IS the factor / the set value** —
  `0` zeroes that stat's multiplicative pipeline rather than meaning "no
  effect". Write `v` into the formula when you mean "scale what I authored".

### `discard` — which computed values are worth granting

Reach decides membership; `discard` decides whether a computed value lands. It
replaced a hidden `is_zero_approx` skip that made "…0.2, 0" and "…0.2 [no 0]"
indistinguishable to an author. `NONE` / `ZERO` / `NEGATIVE` / `NON_POSITIVE`
(default) / `POSITIVE` / `NON_NEGATIVE`, each naming what it drops.

**A debuff aura must opt out.** Its grants are negative by construction, so the
buff-shaped `NON_POSITIVE` default would discard all of them. Every shipped one
(`ninja_core.tres`, `serpent_core.tres`, `blocker_footprint_falloff.tres`) pins
`ZERO`, which is precisely the pre-#900 behaviour: keep the negatives, skip the
zero. `NONE` would be wrong for all three — they pair a negative value with
`ProportionalScale`, so the **source node** computes exactly 0 and must stay
ungranted (`test_a_footprintless_blocker_is_todays_blocker_with_an_inert_aura`
is what catches it).

| Class | `reach` | `metric` | `distance_scale` |
|---|---|---|---|
| Bulwark | `EuclideanRangeFinder` / `HopRangeFinder` | inherited | `FlatScale` |
| Halo | `HopRangeFinder(shell+1)` | inherited | `ShellScale` |
| Ninja | `HopRangeFinder(2)` | inherited | `LinearScale` (falling, `strength` buff) |
| Balanced heal (`HealAuraEffect`, #720) | `HopRangeFinder(4)` | inherited | `ExpressionScale("5 - d")` |
| Serpent A | `null` | `HopMetric` | `ProportionalScale` (positive mods) |
| Serpent B | `null` | `EuclideanMetric` | `ProportionalScale` (negative mods) |

`entity/core/ninja_core.tres` and `serpent_core.tres` (plain `CoreClass`
resources, no dedicated script) are the reference implementations for this table.
Ninja is bounded: an unbounded `ProportionalScale` can't express an *intense,
very-short-range buff*, and pairing it with a bounded reach is the trap the
scale's own docstring warns about.

Serpent's two components land on the same stat as `ADD_BONUS` and sum through one
`ModifierBins.compute` — `Array[Effect]` *is* the composite.

`recompute` is a **full rebuild** (`revoke_all`, then re-grant) and is still what a
core move and `_on_granted` run: `revoke_all` also purges ledger rows whose node a
cascade freed, and a rebuild cannot drift out of sync with the buffed set the way a
diff can. Allocation and deallocation no longer take it, though — **#626 gave them
an incremental path**, `_topology_changed`, which is three branches cheapest-first:

1. the changed node can't be in reach at all → no-op;
2. a `DistanceScale.uses_bound()` scale normalizes by the widest distance in the
   set, so membership alone can move every node's multiplier → fall back to the
   full rebuild;
3. otherwise `_apply_hop_diff` (a metric that dirties on membership change: pull
   the generation-cached raw walk from `AuraDistanceCache`, diff it, touch only
   what moved) or `_apply_membership_update` (one that doesn't: only the changed
   node can need touching, so one metric read and one grant-or-revoke).

`AuraEffect` also owns the **payload seam** the channels share:
`_has_payload()` and `_grant_to(ctx, node, distance, bound)` — the scale is evaluated *inside* the seam now, per modifier leaf, since it needs each leaf's authored value. `TagAuraEffect` is those two
methods and nothing else — the walk, the knobs, the origin rule and the batching
below are inherited, not copied. `HealAuraEffect` (#720) is a third shape on the
same seam: its payload is a per-turn amount rather than a membership grant, so
it overrides `_on_turn_start(ctx)` instead of `_grant_to` (which it leaves a
no-op) and reuses `_distances`/`_bound` directly from inside that hook — the
inherited `_topology_changed` incremental paths still run on alloc/dealloc but
stay harmless, since `_grant_to` never grants anything for this channel.

Reach queries go through `RangeFinder.gather`, never `in_range` in a loop — see
`.claude/rules/graph.md`.

### Batching: one settle per stat per dispatch (#627, #647)

A rebuild revokes a node's OLD grant then re-grants the new one — the same stat
written twice, and unbatched that is two immediate `Stat.value_changed` emissions
where one would do. `recompute` brackets every board it touches (old targets *and*
new, opened before `revoke_all` so the revoke half is covered too) in
`StatBoard.begin_batch` / `end_batch`, closing on every exit path including the
early returns — an unmatched `begin_batch` swallows every later notification on
that board, forever.

#647 widens the bracket from one `recompute` to the whole **hook dispatch**.
`Entity.dispatch` opens the scope with `EntityCombat.begin_dispatch()` and drains
it in `end_dispatch()`; in between, `EffectContext.hold_batch(board)` parks the
board on that deferred-close ledger, which takes ownership and returns `true` —
the aura must then *not* close it itself. So the
Serpent's two auras collapse into one settle per stat instead of one each. Outside
a dispatch (`_on_granted`, a direct `recompute`) `hold_batch` returns false and the
local bracket applies, exactly as in #627. Batching defers **notification only,
never value** — `Stat.get_value()` recomputes from bins per call, so a mid-batch
read is already correct.

## Deferred

- **LifeLine** — "kept alive despite being islanded" overrides the islanding rule.
  It needs a **query hook with a return value** inside
  `nodes_islanded_by_removing_set` / the cascade, not a fire-and-forget notification
  and not a modifier grant. Different hook shape; its own issue (#240). The tag
  channel it rides on has shipped (Known limits below); the grace mechanic
  itself is a design sketch in [lifeline-grace.md](../design/lifeline-grace.md).
- **Presentation** — icon + `get_description()` rendering in the HUD.


## Known limits — file an issue to extend

This is the boundary of what the effect system can express **today**. Hitting one
of these is the signal to file (or revisit) an issue, not to work around it locally.

Two rows left this table in #267 and are now ordinary features: a **non-numeric
marker** on a node/entity (`poisoned`, `marked`) is `EffectContext.grant_tag` —
refcounted on the carrier (`_tags: Dictionary[StringName, int]` on `SkillNode`
and `Entity`; `add_tag`/`remove_tag`/`has_tag`/`get_active_tags`, no
`StatRegistry` entry and no board slot), ledgered alongside modifier rows so
`revoke_all()` sweeps both, radiated by `TagAuraEffect`; and an aura **radiating from its carrier node** rather than the
core is the origin rule `ctx.source_node ?? ctx.core_location`, resolved once in
`AuraEffect.recompute`.

| You want… | Status | Extend via |
|---|---|---|
| An effect that reacts to a **node's own** lifecycle and mutates only that node | Supported for the status shape via `NodeCombat`'s status slice — see [status-effects.md](status-effects.md). General `EffectInstance`-hosted-on-a-node dispatch is not built | A node-local effect bin, when an effect needs its own `_on_*` dispatch on a node |
| A hook that **returns a value** to change *whether* something happens (LifeLine veto) | Not supported (hooks are fire-and-forget `void`) | Query hook — LifeLine, Deferred above |
| An effect on an **unallocated** node (map/environment hazard) | Not supported (node effects are dormant until owned) | A distinct `NodeHazardEffect` feature — no issue yet |
| A spell/tag grant that **survives its granting node** on death | Handled *outside* the ledger (`SpellBook` innate/permanent add) | Spellbook looting — [#204](https://github.com/Koaieus/skill-tree-of-life/issues/204) |
