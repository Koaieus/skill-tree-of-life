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
A spell's status is not authored here but emitted from the load of its `AspectIntake` rows via `Infusion.riders` (ADR 0047, ADR 0060).
The plumbing every mode shares is three statics: `HitLanding.riding(primary, hits, cache)` builds an arrow's or a blade contact's landing (and shares its `hit_key` with the primary), `OnHitEffect.run_all(effects, landing)` runs a list, and `OnHitEffect.keep_mode_agnostic(value, where)` is the refusal setter on `AmmoType`/`SkillNodeAddon`. `HitLanding.stack_scale` is a landing field any mode may read (`ApplyStatusEffect` copies it onto every status); today only spell context writes it.

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
spike ring, toxin and watchtower all author modifiers and no
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

## ExpressionScale formula inputs and semantics (`effects/distance_scale/expression_scale.gd`)

An authored `(d, max, v, h, e, rel) => value` formula, evaluated through
Godot's `Expression`. The escape hatch that makes the closed-form library
optional.

Six inputs, and it returns the value to grant:

- `d` — the metric's distance to this node.
- `max` — the reach bound in the same units, or `-1.0` unbounded.
- `v` — the authored value being shaped (the leaf modifier's
  `value`). Per leaf, so a composite's three leaves get three results.
- `h` — hop depth from the source over the aura's mirror,
  whatever the metric measured; `-1.0` for a node in another component.
- `e` — pixels from the source, whatever the metric measured.
- `rel` — the node's `SkillNode.Ownership` bit as the aura's
  owner sees it: NEUTRAL 1, MINE 2, ALLY 4, HOSTILE 8 (an int, so `rel & 8`
  works as well as `rel == 8`).

```
"5 - d"                     # 5 at the core, 4, 3, 2, 1 — the absolute ladder
"v * (1 - d / max)"         # LinearScale
"v"                         # FlatScale
"v * d"                     # ProportionalScale
"v * (1 - h / 4)"           # fall off by hops on an aura that REACHES by pixels
"v * (1 + int(rel == 8))"  # double on HOSTILE; Expression has no ternary, so bool → int
"[NAN, v][int(h >= 2)]"     # NOT granted inside 2 hops — the escape hatch, see below
```

**0 is a value; `NAN` is absence.** A formula that computes `0` grants a
real +0 under `discard = NONE` — a ledger row, a tooltip line, a `SET 0` on
a derived stat. To grant *nothing* at a node, return
`DistanceScale.NOT_GRANTED`: write the built-in constant `NAN`.
`Expression` has no ternary (`a ? b : c` and `b if a else c` both fail to
parse), so select with an array literal indexed by the bool-as-int:
`[NAN, v][int(h >= 2)]`. Both elements are evaluated; NaN is inert, so
that costs nothing. This is the *escape hatch* — gating ("start after
N hops", "band N..M") belongs in the reach, where a range finder drops the
node before any formula runs and the aura never pays for it. `NONE` is not
an alias: it already names `AuraEffect.Discard` `NONE`. `v / d` at
the source is `inf`, not NaN; `AuraEffect` drops any non-finite result the
same way, so that node is simply not granted.

**`h` and `e` are paid for only when named**: `AuraEffect` asks `wants_hops` / `wants_euclid`
and walks the bounded hop ball (`HopMetric.depths`) or takes the per-node `distance_to` only then.
The 3-arg `scale` path feeds the sentinels `h = -1, e = -1, rel = 0`,
so a formula that never names them evaluates exactly as it did before.
`HealAuraEffect`'s turn-start ramp still calls that 3-arg path, so a heal
formula naming `h`, `e` or `rel` sees the sentinels, not the node's facts.

**`v` is opt-in, and that is the point.** A formula that omits it ignores
the authored number entirely — which is how you say "heal 5, 4, 3, 2, 1"
instead of "some fraction of 5". Mention it when you mean "scale what I
authored". For a MULTIPLY or SET leaf the result is the factor / the set
value itself — see `EffectContext.grant_at`.

**Whether a result lands is `AuraEffect.discard`'s call**, not
this class's. `5 - d` over reach 5 computes a 0 at the rim; the default
`NON_POSITIVE` drops it, `NEGATIVE` keeps it, `NONE` lets the ladder run on
into negatives. The scale never second-guesses its own arithmetic.

**Stateless like every other scale.** `_expr` is compile state — one
parsed `Expression` shared by every entity using this resource — never
anything per-entity. Parsing is lazy and cached exactly as
`ExpressionFormula` does it, and the `formula` setter invalidates so
an inspector hot-edit in the sandbox host takes effect immediately.

## AuraEffect (`effects/aura_effect.gd`)

A buff (or debuff) radiating from a source node to nodes around it,
re-evaluated whenever the world moves under it. The source is the carrier
node for a node-granted aura (keystone/addon), falling back to the entity's
core for an entity-wide one (core class) — see `recompute`'s origin rule.

Four orthogonal knobs:

- `reach` — *which* nodes are touched. `null` floods the whole scope.
- `metric` — *how far* each is, feeding the scale. `null` reuses the
  distances `reach` already produced.
- `distance_scale` — the VALUE each modifier leaf gets at that
  distance, from the leaf's authored `value` (#900). `null` is flat.
- `discard` — which computed values aren't worth granting.

Sign lives on the modifier: negative values make a debuff aura. So the Ninja's
"−1 armor per hop from core, going negative" is
`reach: null, metric: HopMetric, distance_scale: ProportionalScale,
modifiers: [armor ADD_BONUS -1]`. The Serpent is two of these side by side, one
per metric — which is why `Array[Effect]` needs no `CompositeEffect`.

**Stateless.** This resource may be shared by every entity of a class, so it
keeps no buffed-set dict. The applied handles live in the per-grant
`EffectInstance` ledger, and a recompute reads them back from there. A `_buffed`
member here would have every Ninja silently clobbering every other Ninja's aura.

**The PAYLOAD is the swappable state, not the walk.** Everything above —
the three knobs, the origin rule, `recompute`'s batching, and #626's
incremental `_topology_changed` paths — is channel-agnostic. What a
subclass swaps is the pair `_has_payload` / `_grant_to`:
"is anything configured" and "put one grant on this node at this distance".

## Effect base class (`effects/effect.gd`)

Persistent, hook-driven behaviour carried by a `CoreClass`, a `SkillNode`
(a landmark scene's `effects`), or a `SkillNodeAddon`, and dispatched by
the `Entity` that owns it.

**Stat math — a formula included — is a `StatModifier`, not an Effect.**
Reach for an Effect only for behaviour that needs a lifecycle hook.

**Not to be confused with `OnHitEffect`**, which is transient: it fires
once as a spell lands on a node and keeps no state. An `Effect` is granted,
lives, reacts to gameplay moments, and is revoked. Sibling concepts, not a
hierarchy.

**Composition, not a subclass zoo.** There is no `TurnStartEffect` /
`BattleStartEffect` split — those would be uncomposable (an effect can't be
both). Triggers are *methods*; the composite is an `Array[Effect]` on
the carrier, which the Godot inspector edits natively. So no `CompositeEffect`
is needed either.

**Hooks are declared, not inherited.** This base defines none of the `_on_*`
world/combat hooks, so `has_method()` is an exact test of "does this effect
care" — and `Entity` buckets by hook once at grant time, making dispatch
O(interested) rather than O(all effects). Implement only what you need:
```
func _on_core_moved(ctx: EffectContext, from: SkillNode, to: SkillNode) -> void:
    ...
```

The two lifecycle hooks below are the exception — defined here and always
called. Everything else is optional and listed in `HOOKS`.

**Effects are shared resources.** One `.tres` may sit on many entities.
Never store runtime state on the effect; use the `EffectInstance` ledger via
`EffectContext`.
