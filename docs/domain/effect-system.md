# Effect system (#4)

Persistent, hook-driven behaviour attached to an `Entity`. **Stat math — a
formula included — is a `StatModifier`; an `Effect` is for behaviour that needs
a lifecycle hook** (grant/revoke-time work, turn start, on kill, core moved, an
aura re-evaluated as distances change). A core class, a landmark, or an addon
reaches for one only for that.

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
| `_on_turn_start` / `_on_turn_end` | `Entity.begin_turn` / `finish_turn` |
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
`entity/keystone/keystone_skill_node.tscn` whose stat payload is plain
`SkillNode.modifiers` SubResources of the `.tscn` (#336; supersedes #929's
placement on `SkillNode.effects`). Owner call, 2026-09-24: a pure stat bundle
belongs in the node's `modifiers` array, not wrapped in a `StatEffect` — wrapped,
the tooltip read an empty aura and "(no modifiers)". `SkillNode.effects` is for
a landmark that does something behavioural. The old
`Keystone` resource — identity + an `effects` payload that `stamp()`ed
presentation onto a carrier node — mirrored a subset of `SkillNode`'s own
authoring surface and is deleted; its payload semantics (live reference, read
at every allocation, one shared resource safe across entities) are exactly
`SkillNode.effects`'.

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
one, and `Edge.gd` holds one.)

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

Ninja shipped bounded rather than the unbounded-debuff shape this table used to
show (that shape lives on as `test_aura_effect.gd`'s generic direction-agnostic
`ProportionalScale` demo, not as the class) — the design doc calls for an
*intense, very-short-range buff*, and an unbounded `ProportionalScale` can't
express "bounded": pairing it with a bounded reach is the trap the scale's own
docstring warns about. `NinjaCore`/`ninja_core.tres` and `SerpentCore`/
`serpent_core.tres` (#39) are the reference implementations for this table now.

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
  itself is a design sketch in [status-tags.md](../design/status-tags.md).
- **Presentation** — icon + `get_description()` rendering in the HUD.
- **Node-local effect bin — SHIPPED (#868 hub, #872/#878/#879).** This cell used
  to describe a coherent-but-empty sibling to `node_board`, waiting on "the first
  effect authored to react to a node's *own* lifecycle and mutate *only*
  node-local state." Poison/Blindness/Armor Break were exactly that trigger, and
  the bin that shipped is narrower than the speculative one this entry used to
  sketch — not a generic `EffectInstance` bin with its own `_on_*` dispatch, but
  a purpose-built **status slice**: `StatusDef` (`effects/status/status_def.gd`,
  a `.tres`-authored resource — id, tags, `power_max`, a `decay` slot,
  `reapply` policy, `cure_per_hp`, `on_dealloc`, display identity) plus a
  per-node `NodeStatus{power}` row, held on `NodeCombat._statuses` (#872) beside
  `_tags`/`_board` — "on NodeCombat, like node HP" (owner). Application is a
  `StatusInstance : HitInstance` pushed by `ApplyStatusEffect : OnHitEffect`
  (#878), landed via `NodeCombat.apply_status`/`land_on` on whichever
  `CombatWorld` the applier hands in — same shadow/live split as every other
  hit. Ticking is an owned-set sweep in
  `Entity.resolve_turn_end` — its own step of `TurnManager.end_turn`, after
  the cursor is nulled and before `finish_turn` (ADR 0040, #1256): the
  entity-host tick first, then the owned nodes over a snapshot of the owned
  set (the one regen already walks), skipping a node stripped mid-sweep, then
  one `StatusSpread.on_tick` sweep per def carried by an owned node whose
  `spread` slot is set (diffusion comes in two modes: `FlatDiffusion` seeps 1
  stack past a crowding threshold, `FractionDiffusion` a floored share of the gap)
  — senders the owned set, landed through
  `SpreadApplier` on the live world; defs with a null slot pay nothing. Every
  played-out turn, the first included; never on `abandon_turn` (a death, the
  status sandbox's `disarm`) nor an adopted resync cursor. A tick's damage
  suppresses the owner's next turn-start regen; a tick that kills the actor
  hits `abandon_turn` as a no-op and `end_turn` still hands on. Peers
  reproduce it, since `EndTurnCommand` runs `end_turn` everywhere. All statuses void on any deallocation path
  (`NodeCombat.release_statuses()`, which hands back the rows) —
  `StatusDef.OnDealloc` reserves a `LINGER` door but only `CLEAR` is built.
  The released rows can SPILL: exactly two feeders note them on the world's
  removal collector before the strip — `EntityCombat.apply_cascade`'s per-node
  body (cause DEATH, both worlds; every forced removal, entity death included)
  and `AllocationSystem._deallocate_unchecked` (cause DEALLOC) — and
  `CombatWorld.flush_removals()` runs each def's `spread.on_removed` once per
  beat over the beat's whole removed union, so a node stripped in that beat
  never receives. A beat fed a rebuilt record (a live replay) lands the
  recorded transfers and computes nothing — spill is received, not reproduced. A beat: one `deallocate` / `deallocate_set`; one
  `schedule_index` group in `OutcomeApplier.apply`; one wave in
  `SpellResolver.resolve_against`; one turn-end tick step (flushed before its
  diffusion sweep); a gate-flip command flushes as its own beat; an
  entity death never flushes, it belongs to the beat that killed it. A bare `force_deallocate` outside a cascade releases
  without spilling. Curse is authored with `SpillSpread` (both triggers, 1.0,
  Mine). `network/graph_snapshot.gd` carries `(status id,
  power)` rows in resync, and `WorldFingerprint` folds them. Concrete defs:
  `BlindnessStatus` (#873, MULTIPLY on vision/sensor range), `ArmorBreakStatus`
  (#877, MULTIPLY on armor), `PoisonStatus` (#874, unmitigated
  `DamageInstance.Type.TRUE` damage on `_on_tick`, flat or `%`-of-max-hp per
  `basis` — `HitInstance.AmountBasis` (flat, % max, % current), resolved in `DamageInstance.land_on`,
  not a poison-local enum — can kill through the ordinary `notify_depleted` cascade).

## Status effects — the DoT model

The status slice above (`StatusDef` + a per-node `NodeStatus{power}` row) carries
four damage-over-time families, one per defensive axis they answer. The *why* —
one family per axis, uncapped halving stacks, the rejected timers — is
[ADR 0022](../adr/0022-one-dot-per-defensive-axis-stacks-halve-uncapped.md);
the hosts (node, or the entity once the row falls through a cracked core) are
[ADR 0024](../adr/0024-status-effects-have-two-hosts-and-fall-through-a-cracked-core.md).
What could still come (cures, contagion, the other families' arrows and spells)
is `docs/design/damage_over_time.md`.

| Family | Denomination | Answers | Weak against |
|---|---|---|---|
| **Poison** | flat HP per stack per tick, unmitigated | armor, a sub-zero `min_damage_taken` | bulk |
| **Corruption** | % of max HP per stack per tick, unmitigated | bulk (the CON stacker) | rarity and cure only |
| **Curse** | raises `min_damage_taken` by its stacks | armor: every hit lands again | deals nothing alone |
| **Wither** | multiplies `healing_received` down, below zero | the heal aura and regen | nodes nobody heals |

There is **no per-tick clamp**: every family is lethal in sufficient amount.

**Stacks.** A row is one float, `power`. Each tick `_on_tick` spends the
pre-decay stacks, then the row decays by its def's shape (the table below); a
FRACTION row clears below 1. Stacks are uncapped.

**Landing.** `landed = fold(<family>_stacks_per_hit(attacker), base_add = per_hit)`
— `StatusDef.stacks_per_hit`: the per-hit amount authored on the applier (ammo
type, on-hit effect, blade vertex) is the `base_add` of the attacker's stacks
stat, whose INCREASE/MORE scale the total ([ADR 0029](../adr/0029-related-stats-compose-through-parents-folded-at-read-and-every-stat-takes-every-bin.md)
— no separate potency stat). Computed once at land on the landing world, never
floored (1 × +49% lands 1.49). Hit size never scales stacks. The four families'
stacks stats share one parent umbrella, `dot_stacks_per_hit`, which lands more
stacks and never scales damage; blindness (`blindness_stacks_per_hit`) and
armor break (`StatusDef.stacks_stat_id`) sit outside it.

**Resistance** (`poison_resistance`, …, default 0, a fraction) is read on the
**host** and filters the accumulated row at effect time, never the incoming hit
([ADR 0031](../adr/0031-status-resistance-filters-the-accumulated-row-at-effect-time-on-the-host.md)):
each apply and each tick counts `row − cancelled`, with
`cancelled = ⌈row × res − ½⌉` clamped to `[0, row]` — round half-down
(1·1% → 1, 1·50% → 1, 1·60% → 0, 10·25% → 8, 20·1% → 20). The row itself decays
from its unresisted size. At **≥ 100%** stacks do not land (the authority
resolves the hit to 0 and the record carries it); a standing row deals 0 and
still decays. `StatusDef.next_tick_damage` is the first term of the health-bar
projection, which walks the raw row down tick by tick, resisted then floored.

**The regen gate.** A DoT tick is damage and closes the node's regen gate
(`node-hp.md`). The one exception is wither: a heal inverted by
`healing_received < 0` is damage that leaves the gate open, so a withered node
left alone ramps its regen up and heals itself to death, and the core aura
unheals its own neighbourhood — `NodeCombat._withered_heal`.

**Decay shapes.** Falloff and duration are per def, never stats (#1060):

| Status | Shape (`FractionDecay` / `FlatDecay`) | Total per stack applied once |
|---|---|---|
| Poison | FRACTION, retains 0.5 | 2 |
| Corruption | FRACTION, retains 0.8 | 5 stack-ticks |
| Curse | FLAT 1/turn | a window of N turns |
| Wither | FRACTION, retains 0.75 | 4 |
| Blindness | FRACTION, removes 0.7, ACCUMULATE | see [node-subtypes.md](node-subtypes.md) decision 20 |
| Armor break | FLAT | |

Authoring gotcha: the `.tres` knob `FractionDecay.fraction` (the `decay` sub-resource) is the fraction
**removed**, so a row retaining *f* is authored as 1 − *f* (corruption 0.2,
wither 0.25); blindness's 0.7 is the fraction removed (#1090). The shape law is
`test/unit/effects/test_status_decay_shapes.gd`.

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
| An effect that reacts to a **node's own** lifecycle and mutates only that node | Supported for the status shape (poison/blind/armor-break) via `NodeCombat`'s status slice (#872/#878/#879) — see Deferred above. General `EffectInstance`-hosted-on-a-node dispatch is still not built | Node-local effect bin — see Deferred above |
| A hook that **returns a value** to change *whether* something happens (LifeLine veto) | Not supported (hooks are fire-and-forget `void`) | Query hook — LifeLine, Deferred above |
| An effect on an **unallocated** node (map/environment hazard) | Not supported (node effects are dormant until owned) | A distinct `NodeHazardEffect` feature — no issue yet |
| A spell/tag grant that **survives its granting node** on death | Handled *outside* the ledger (`SpellBook` innate/permanent add) | Spellbook looting — [#204](https://github.com/Koaieus/skill-tree-of-life/issues/204) |
