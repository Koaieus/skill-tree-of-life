# The attack timeline contract

This is what every attack mode is built *towards* — a single contract all three
modes fulfil, so that adding a fourth mode, or an on-hit effect, or an ammo type,
is a matter of satisfying a written spec rather than re-deriving what "when does
this happen" means from three different code paths. Why the contract has this
shape, and the two timelines that lost, are
[ADR 0011](../adr/0011-one-attack-timeline-contract-for-every-mode.md).

The game-design side of attacks (damage formulas, the color triangle,
dismemberment) lives in `../design/combat_system.md`. The *code shape* of the
in-turn attack flow lives in `attack_plan_system.md`. **This doc covers only
the timing model**: which world state each part of an attack reads, and at
which clock.

Read this before changing `resolve()` on any `AttackPlan`, before touching
`OutcomeApplier`, and before adding anything that happens "during" an attack.

---
## The invariant

> **Resolution emits candidate landings in time order. One applier walks them
> in that order and re-evaluates each landing's gate against live state before
> applying it.**

**This is the AUTHORITY's timeline.** Under
[multiplayer-sync-model.md](multiplayer-sync-model.md) the host resolves on a
shadow, records an `AttackRecord`, and replays that record through
`OutcomeApplier` like any peer. A *peer* receives the record and replays its
deltas through the same applier loop; it re-runs no gate, re-reads no live
offense and computes no combat number, because mitigation is node-local, an
earlier beat's cascade changes what a later beat lands on, and a target may sit
under fog it knows nothing about. Every "re-read at land time" sentence below
describes the resolving machine.

Two halves, both load-bearing:

- **Resolution is up-front and lands on a shadow.** It produces an
  `AttackOutcome` that has **already landed** in the `CombatWorld` it was
  handed — a result, not a plan of landings. That is safe as a preview, as AI
  scoring input and as the wire payload because the world it mutates is a
  throwaway shadow (see "The world is ALWAYS a shadow").
- **Application is staged and live.** Each landing's *gate* — "is this target
  still allocated? still hostile? is this blade vertex still alive?" — is
  re-checked at the moment the landing applies, not when it was planned.

The gate is a **veto, not a re-plan.** A landing that fails its gate is
dropped. Application never *discovers new targets*; that would make resolution
a lie and break the preview. Re-aiming a wasted shot at some other live target
is explicitly out — it is the one shape of this feature that breaks the
contract.

### What a failed gate looks like — settled, and it differs per mode

The three modes do not share a visual answer, because they do not share a
failure *shape*:

- **Melee: ignore it, no visual at all.** Hit-scan has no concept of a dud —
  only "hit" or nothing. A blade sweeping over an already-dead node is
  indistinguishable from sweeping over ground that was never allocated, and
  should look that way.
- **Magic: it cannot happen.** The next wave's candidate list is built by
  querying ownership live at selection time, so a dead node is simply never a
  candidate. There is nothing to render.
- **Ranged: the arrow lands inert.** This is the only mode where the gate can
  fail *after* the visual has committed — the projectile is already in flight
  when the target dies. It arrives and plays a dud beat: desaturated, no bloom,
  no damage number. Same visual language as a spike-popped blade vertex
  dimming. Legible, and it shows the player their volley overkilled.

### Ranged renders EVERY arrow, whatever the arrow did

The dud beat is one *outcome* an arrow can have, not the only non-standard one
([ADR 0012](../adr/0012-every-arrow-renders-whatever-it-did.md)). A landing may
also mitigate to exactly zero, or — where the defender's net `min_damage_taken`
is negative, which `bunker_addon.tscn` authors deliberately — mitigate *below*
zero and be reclassified to `Kind.HEAL` by `NodeCombat.take_damage`. All of
these still get an arrow.

`ArrowVolleyCoordinator.play` therefore iterates `outcome.hits` directly and
**must never filter on `HitInstance.kind`** — a volley whose hits all flipped to
heals would spawn nothing while the player had spent the AP.

The one entry it skips is skipped **by class**: a typed arrow's riders
(`AmmoType.on_hit_effects`) ride `outcome.hits` as `StatusInstance`s right after
its arrow — same origin, target and beat — and are not arrows, so they draw
nothing. `BattleSystem._consume_volley` counts shots on the same distinction.
`AttackOutcome.damage_hits()` stays for the *scoring* passes (`AiCombatScorer`,
`AiBladeRollout`) that want damage only; filter at the call site that means it,
never in a render pass.

## Why: the fiction has to hold

The rule falls out of what an attack visibly *is*.

*Melee.* A blade swings into an arm of enemy nodes, kills the one closest to
the core, and the rest of the arm — now islanded — is force-deallocated. The
blade sweeps on across nodes that are already dead. Their `SpikeAddon`s do
nothing, because a severed arm does no work. You don't disarm someone and then
get shot by the gun falling to the floor.

*Magic.* A wizard lobs a bolt at a target. It lands, deals damage, and a
smaller bolt jumps from that node to each hostile neighbour. If the first
landing *killed* the target, that node is unallocated for the rest of the
cast — so a spell that only propagates to hostile nodes cannot bounce back into
the corpse it just made.

Mind the wave arithmetic: **wave 0** hits the seed, **wave 1** hits its
neighbours, and **wave 2** is the first expansion where the seed can be
selected again (it is `visited` during the 0→1 expansion, so wave 1 was never
the risk). A test for this needs `max_hops >= 2` and a `max_visits_per_node`
that permits a revisit, or it proves nothing.

Both stories are the same rule: **kill state resolved at wave N is visible to
every expansion from wave N onward.**

## The clocks

| Clock | When | What it is |
|---|---|---|
| **Plan** | while the player is arming | Live, continuously re-read. Highlighting, range rings, validity. Nothing is committed. |
| **Commit** | at launch | The attacker's offense is snapshotted (damage per shot, blade vertex damage, spell damage). |
| **Resolve** | `AttackPlan.resolve_against(world)`, once, at launch | Runs on a shadow. Snapshots the *candidate set*, stamps the order, emits an `AttackOutcome` already landed in that shadow. |
| **Land** | per landing, in `arrival_time` order | Live. Gate re-check, then mitigation, then mutation, then any cascade — all synchronous within the beat. |

## What is read at which clock

| Input | Clock |
|---|---|
| Candidate landing set (which nodes *could* be hit) | **Resolve** |
| Ordering of landings (authored into `arrival_time`; `OutcomeApplier` sorts on it) | **Resolve** |
| Landing gate (target still allocated / still hostile / vertex still alive) | **Land** |
| Attacker offense (`ranged_damage`, blade vertex damage, spell damage) | **Commit** |
| Crit *decision* (`crit_chance` roll, `SpellDef.crit_conditions`) | **Resolve** — one shared `CritRoll`, see below |
| Crit *multiplier* (`amount ×= crit_multiplier`) | **Land** — base `DamageInstance`/`HealInstance.land_on` |
| Amount *basis* (`HitInstance.basis` — FLAT HP, `PERCENT_MAX` of the target's max hp, or `PERCENT_CURRENT` of its current hp) | **Land** — `HitInstance.resolve_amount`, ahead of the crit multiply; resolves once and flips itself to FLAT, so a rebuilt record never re-scales. Sizes the number *before* `Mitigation` — bypass is `Type.TRUE`'s axis, not this one |
| Defender mitigation (`armor`, `min_damage_taken`) | **Land** — `Mitigation.apply` inside `SkillNode.take_damage` |
| Cascade / dealloc / entity death | **Land**, synchronous |

### Offense is snapshotted at commit time

The split is **set frozen, offense frozen, defence live**. Owner ruling,
@Koaieus, 2026-08-23:

> **ranged** — *"snapshot damage at launch… recalculating while arrows are
> mid-flight makes no sense. If the first 2 arrows kill the target, 1) iff we
> were to recalculate the damage, it'd be for the remaining 3 arrows, which do
> nothing."*
>
> **melee** — *"you copy a blade, then swing it around. The copy is essentially
> disjoint from the graph and shouldn't update its damage while it swings.
> Copy-time is where it's all at: forge blade then use it."*
>
> **magic** — *"the caster casts a spell, at that moment the stats of the caster
> and/or casting node are important, beyond that it's a spell in flight — it
> carries its own. Makes no sense for the cast spell to listen to any changes of
> the caster while in flight."*
>
> — @Koaieus, 2026-08-23

| | Clock | Because |
|---|---|---|
| Candidate set | Commit | resolution must not discover targets |
| Attacker offense | Commit | the projectile / blade / spell carries what it left with |
| Landing gate | Land | the world it arrives in decides whether it arrives at all |
| Defender mitigation, cascade | Land | that is the defender's live state, not the attacker's |

**Nothing is lost by freezing offense.** A volley whose early arrows already
killed the target is handled by the **gate**, which vetoes the late ones
entirely; a stale number on an arrow that never lands is not an error. Where the
gate lets a hit through, the target is still there and the attacker's own
launch-time strength is the honest number.

Each mode's snapshot point:

- **Ranged** — `RangedDamageFormula.compute`, once per scheduled shot, all of
  them before any landing. `_read_offense` is the only read.
- **Melee** — `MeleeAttackPlan.build_blade_state()` stamps `vertex_damage[i]`
  from each source node's `blade_damage`. Forge, then swing.
- **Magic** — `SpellResolver.impact_damage`, once at cast. It has a second,
  independent reason to freeze: a per-hop re-read would compound INT (INT² by
  hop 2).

**Ranged's freeze rests on a relationship between two authored numbers**, pinned
by `test_ranged_damage_formula.gd`: `PresentationTempo.volley_flight_time`
**must stay greater than** `volley_stagger_span`, so the last arrow launches
before the first lands. Otherwise an arrow would be loosed *after* an earlier
one had cascaded the board, "snapshot at launch" and "snapshot at resolve"
would silently diverge, and damage would merely go stale with no test failing.

### The crit split — the one input that spans two clocks

- **The decision cannot wait for land.** `MagicBounceCoordinator` stamps
  `Projectile.crit_tier` when it *spawns* a bolt, and `Projectile` fires
  `_on_crit` at flight start — both strictly before the applier lands that
  wave. Magic's `SpellDef.crit_conditions` are resolve-bound anyway: they read
  `CastSpell` propagation state (predecessor, incident count) that exists
  nowhere else.
- **The multiply happens at land**, in base `DamageInstance`/`HealInstance.land_on`,
  because **a gated hit must not carry a multiplied amount**: a veto returns
  before `super.land_on`, so a dud's `amount` stays exactly what was loosed.

`crit_chance` / `crit_multiplier` are read at resolve, so a mid-attack change to
either is not seen by hits already in flight.

A single seeded stream serves a whole attack, so **draws are consumed in
landing order** (the structural `schedule_index`, never seconds). The draw lives
inside the landing itself — `OutcomeApplier.land_one` calls `CritRoll.decide`
off the outcome's `crit_stream` right before the hit lands, reading the landing
world — so the two orders cannot drift apart; if they did, crits would stop
reproducing under a replayed seed. A rebuilt record carries no stream and lands
its recorded crits.

## Per-mode contract

Every mode satisfies all four. The *mechanism* differs; the contract does not.

1. **Emit candidates in time order**, each stamped with a real
   `HitInstance.arrival_time` in seconds from launch.
2. **Re-evaluate ownership and liveness at land time**, per landing.
3. **Snapshot attacker offense at commit time**, and never re-read it at land.
4. **Resolve against a shadow** (below), so AI and preview never mutate the
   real world.

### Magic

`SpellResolver`'s `while not wave.is_empty()` loop is the wave model above, with
application inside it:

```
reduce incidents  →  on-hit effects  →  LAND  →  expand next wave
```

so `config.filter.allows` and `max_visits_per_node` see post-land ownership: the
fireball story holds. `PropagationEvent.beat` × a per-wave interval is magic's
`arrival_time`. Details under "The candidate-set half" below.

### Melee

**The scan stays pure, and the interleave sits one level up.** `BladeHitScan`
never touches the applier: its `PhysicsShapeQueryParameters2D.exclude` is built
once per resolve, and its purity is load-bearing because `ai_blade_rollout.gd`
runs it on `WorkerThreadPool`. `MeleeAttackPlan.resolve_against` holds a
`BladeHitScan.Sweep` open across samples and drives **sim → scan → land** one
sample at a time.

The **ownership filter runs at consumption time**, not query time:
`MeleeAttackPlan.collect_target_excludes()` excludes only the attacker's own
nodes and the blade members — never `not sn.is_allocated()` — and
`BladeDamageInstance.land_on` re-checks `is_allocated()` / `owned_by` /
spike-pop per event, live, as `OutcomeApplier` lands it. `BladeHitEvent.t` is
melee's `arrival_time`.

**The preview resolves too, on its own shadow.** Melee's aim-time preview is a
**real** `_resolve_swing` against a `CombatWorld.shadow()`, run once per
selection change and replayed by `MeleePreview` — the same shadow path
`AiCombatScorer` uses and `BattleSystem._compute_record` runs at commit.

- **It publishes nothing.** `_resolve_swing` returns a `SwingResult` bundle
  (`attack/melee/swing_result.gd`); only `resolve_against` writes it onto the
  plan's `last_*` fields, so a prediction never overwrites the artifacts
  `MeleePreview.launch` replays for the swing the authority landed.
- **It announces nothing**, as no shadow does (`CombatWorld.is_shadow`) — the
  pop cue rides the mutation clock.
- **It is a prediction, not an authority.** It may differ from the host's
  resolve by last-ulp float differences across platforms, and because the
  preview runs on the unstamped (0) crit stream while the committed swing
  stamps a fresh one. Both are accepted mispredicts; neither lets a peer
  re-decide a landing from its own sim.

**Severance is interleaved, and the gate is fed by the applier.** A spike pop is
decided at land time, so *what a swing severed* is not known until the batch
containing that contact has been applied. The gate is reached from
`BladeDamageInstance.land_on` **inside** `OutcomeApplier.apply`'s walk — never
from the scan. `resolve_against` bakes the swing **optimistically**, walks it
sample by sample landing each sample's contacts as their own sub-`AttackOutcome`
(compile → same crit rng → `apply` → merge), and on a pop **re-bakes from that
sample** with the dead vertex frozen, its constraints and driver gone, and drag
written onto whatever it orphaned. Everything lands in true `t` order on the
shadow, so two landings on the same node see each other's mitigation in the
order they happened. Crits are rolled per batch, after earlier landings applied
(`test_batched_crit_rolls_equal_one_global_roll` pins the stream); a swing that
friendly-fires a node whose depletion changes the **attacker's own**
`crit_chance` can therefore crit differently late in the swing — by design.
Detail: `docs/domain/melee-blade-sim.md` ("The preview is a real resolve,
replayed").

### Ranged

The degenerate case: candidates sorted by `arrival_time`, gate re-checked per
landing, damage snapshotted at launch and never re-read. Plus the volley ramp,
below.

---

## The world is ALWAYS a shadow

Magic gates during candidate selection (wave N+1's filter must see wave N's
kill), so resolution itself mutates; melee and ranged gate at *consumption*.
One rule covers all three: **every resolution runs on a `CombatWorld.shadow()`,
and the real world is mutated only by `OutcomeApplier` landing a rebuilt record**
(owner call, 2026-08-23: "shadow always"). Nothing needs suppressing, no
"simulation" flag exists, and no preview caller is a special case. How the
shadow's state is split from its notifications and what it copies:
`docs/domain/entity-combat.md`.

### Landing against a world: `CombatWorld`

```
record replay (every machine): OutcomeApplier.apply(outcome, CombatWorld.live(),  clock)
resolution, always:            OutcomeApplier.apply(outcome, CombatWorld.shadow(), clock)
```

`combat/combat_world.gd` looks each target's state up somewhere else; the same
`OutcomeApplier` loop, per-mode gates and mitigation run in both. **The world is
a required parameter, never a defaulted one** (owner call 2026-08-23): a
`world = null` meaning "live" would put an implicit live branch back inside
`OutcomeApplier` and turn "the sim and the real path agree by construction" back
into "by discipline". Same rule on `BladePopResolver.LiveGate.admit`.

`HitInstance.land_on(node: NodeCombat, world: CombatWorld)` — the hit's `target`
stays a real `SkillNode` because that is its **identity** (what a record
serializes, what a fogged peer resolves by `stable_id`, what every VFX observer
reads). Only the **state** it mutates is swappable, by one dictionary lookup;
there is no preview flag anywhere in the chain.

A shadow world grows on demand, at two grains. The first hit on a node whose
owner is not yet snapshotted snapshots that owner's *entity* (stat board, effect
twins, owned-set mirror, core board); each further owned node's board is cloned
only when the world is first asked about that node (`EntityCombat.shadow_for`).
Late is the same as up front because a shadow resolve never writes the real
world, and only the entities and nodes an attack touches are paid for. The
per-node grain ends the moment anything entity-wide runs (`cascade_set` /
`apply_cascade`, `simulate_entity_death`, a shadow `dispatch()`, `owned()`):
`_materialize_all` mints the rest first, so a cascade set is computed over the
whole subgraph — a node fifty hops away is still in it.

**No shared shadow `GraphMirror` is needed, and that rests on one assumption:**
topology never changes mid-attack, so islanding and propagation walk the *real*
graph while only ownership and stats route through the shadow. It is pinned by
`test_a_full_shadow_resolve_changes_no_topology`; a displacement or terraform
mechanic that severs or adds an edge mid-cascade would break it.

### The candidate-set half: `resolve_against(world)`

`SpellResolver` **lands each wave before expanding the next**, so
`config.filter.narrow(...)` on wave N+1 selects against a world in which wave
N's kills have happened. Two things move together:

1. **The wave loop lands.** Between "reduce incidents" and "expand next wave",
   the wave's hits go through `OutcomeApplier.land_one` — the *same* landing
   every other path uses, so there is exactly one implementation of "land a hit".
2. **The filters ask the world, not the node.** A hit's target stays the real
   `SkillNode`, so `to.ownership_bit(caster)` reads a node that is *still alive*
   whatever the resolver did. `PropagationContext.world` is where the question
   goes, via `ownership_bit_of` / `is_allocated_in_world`; `OwnerFilter` and
   `ExpressionFilter` are the two callers.

Magic's crit roll draws as `land_one` lands each hit, wave by wave — the same
landing-time draw ranged and melee make.

**`resolve_against(world)` returns an outcome already landed in `world`** — the
contract for all three modes. `resolve()` mints a throwaway shadow, resolves,
and frees it; every preview, tooltip and AI rollout calls it.

### The authority replays its own record

```
authority: resolve on a shadow -> capture the AttackRecord -> confirm/broadcast
every machine, authority included: rebuild that record -> land it on the BeatClock
```

`BattleSystem` has one launch path (`apply_launch_command`). The payload decides
which half runs — an empty record means "nobody has computed this yet" — but
there is no apply step for the machine that computed it: the host is a peer of
itself; it is the only one that computes, not the only one that replays.

**The capture → rebuild round trip is load-bearing.** Every land-time write is
one-shot: `CritRoll.apply` multiplies `amount` in place, `hp_before` /
`hp_after` get overwritten, and a `HitInstance.deallocations` left over from the
shadow would make `BattleSystem._on_node_depleted` take its *recorded* branch
and re-apply a stale cascade set. Rebuilding mints fresh hits. Do not optimise
it away.

**An announcement made during resolution has no audience.** The melee spike-pop
cue is therefore *recorded* on `HitInstance.popped_vertex` by the gate running on
the shadow, carried by the record, and emitted by `OutcomeApplier.land_one` as
the hit lands — on every machine. Any future in-resolution announcement needs the
same treatment.

### `AttackOutcome` is the result, not a plan

`resolve_against(world)` — a throwaway shadow for a preview, the authority's own
shadow for a launch — is one code path, never the real world.

- **`AttackPlan` holds the inputs.** Change one and the outcome is recomputable.
- **`AttackOutcome` is *the* deterministic result** of those inputs.

`HitInstance.effective_amount` is filled on every landed hit (0.0 only for a
gated hit, which never reached mitigation — what `gated` distinguishes from
"their armour held"). Totals, per-node damage, kill lists and the enemy/friendly
healing split are accessors over `outcome.hits`. XP is the exception: it lives
in `LootSystem`, via its `preview_kill_xp` query.

---

## Ordering and `arrival_time`

Every hit carries a real `arrival_time`, stamped by `OutcomeSchedule` from the
structure its resolver records: with the world mutating on the reveal clock, an
unstamped hit would mutate simultaneously with every other.

### The ranged volley ramp

Allocation order never influences a combat outcome: firing order is authored
from geometry, nothing derives from `GraphMirror._node_ids` iteration order.

```
rank reaching leaves by euclidean distance to target, ascending
    tie-break: SkillNode.stable_id          # wire-legal, minted by Graph
wave-major fill (#957): each wave, every ranked leaf with a shot left fires
    one arrow in rank order; waves repeat until N
ammo types along that schedule order, walking RangedAttackPlan.ammo — the
    ordered [{type, count}] list, the player's card order (ADR 0051)
d_min, d_max   = nearest and furthest distance in the volley
frac_i         = (d_i - d_min) / (d_max - d_min)   # 0 .. 1; 0 if the span is 0
key_i          = (wave_i + frac_i) / waves         # 0 .. 1; == frac_i for one wave
```

**Since #543 the resolver records only structure about timing — since #957
that structure is `(wave, frac)`, folded into one key.** `key_i` is stamped
onto `HitInstance.structural_key` — the resolver emits structure, never
seconds. One volley is ONE ramp: waves sit back-to-back inside it and
`volley_draw_time` is paid once, so the key divides by the wave count to stay
in `[0, 1]` (the `RAMP` branch's assumption). The last shot of wave *k* and the
first of wave *k+1* share a key; the `(structural_key, original_index)` sort
keeps them in wave order, they merely land on one beat. Turning a key into a

The resolver records only structure about timing: `key_i` is stamped onto
`HitInstance.structural_key` — the resolver emits structure, never seconds. One
volley is ONE ramp: waves sit back-to-back inside it and `volley_draw_time` is
paid once, so the key divides by the wave count to stay in `[0, 1]`. The last
shot of wave *k* and the first of wave *k+1* share a key; the
`(structural_key, original_index)` sort keeps them in wave order. Turning a key
into a clock is `OutcomeSchedule.compile`'s job, in its `Cadence.RAMP` branch,
off the authored `PresentationTempo`:

```
launch_time_i  = volley_draw_time + key_i * volley_stagger_span
arrival_time_i = launch_time_i + volley_flight_time   # constant, NOT distance/speed
```

so a slow-motion replay (a lower `combat_time_scale`) stretches the compiled
schedule instead of the resolver re-authoring one.

**The ramp is metric, not ordinal.** Normalizing on *distance* means a clustered
firing line looses as one salvo and an outlier owns the tail of the window; the
volley's rhythm reads the shape of your territory. `d_max = d_min` (n == 1, or
perfectly equidistant leaves) is a degenerate span, guarded exactly: everyone
fires on the same beat. Distance is pure geometry off `global_position`, ties
break by `stable_id` in the ranking, and `OutcomeApplier`'s stable
`(arrival_time, original_index)` sort preserves them through equal
`arrival_time`s.

**Flight time is a constant, not `distance / PROJECTILE_SPEED`** (owner call,
2026-08-20). The fiction is the arc: a point-blank shot is lobbed nearly
straight up, a distant one goes nearly flat, and both take about the same time
to come down. Mechanically:

- **The launch span and the arrival span are identical** (both
  `volley_stagger_span`). With a constant projectile *speed* the arrival span
  would be `volley_stagger_span + (flight_far - flight_near)` — always wider,
  and widening with the size of your territory, so a big empire's volleys
  would smear out while a small one's stayed crisp.
- **Arrival order == firing order == distance order**, unconditionally. No
  ratio between stagger and flight can invert it, so armor-reducing ammo has an
  order it can rely on without a caveat.
- **A single projectile speed stops being the timing authority.** The
  animation still needs one — it is now *derived* per shot
  (`distance / volley_flight_time`) rather than the input the schedule is
  built from.
- **Nearest fires first and arrives first.** Note ranged is single-target —
  every reaching leaf shoots the *same* node — so what ripples outward is the
  **firing**, across the attacker's territory from nearest leaf to furthest;
  the impacts all converge on one point, in that same order. (Real bow infantry
  range in the same direction.) The choice therefore sets *resolution* order at
  the target, which is what armor-reducing ammo needs, not a visual wave of
  impacts.
- **`volley_stagger_span` is fixed**, so a 4-shot volley and a 100-shot volley
  take the same wall time. This is what makes the "blot out the sun" fantasy
  readable — a hundred arrows in the same window rather than a hundred×stagger
  crawl.
- **`volley_draw_time`** is a windup phase before the first release — leaves
  visibly draw before loosing (1.5 s authored, #1048; 0.0 is the escape
  hatch). It is an awaited presenter beat (ADR 0027), not a schedule offset.
  The camera spends its head, `volley_windup_pivot_focus`, on the firing
  centroid at the player's zoom and the rest drifting un-followed onto
  `{centroid, target}`; the follow opens at first release and the landing
  tighten (`wave_landing`) fires at LAST release.
- **`t = 0` is the start of the draw**, not the first arrival. Every
  `arrival_time` is measured from the moment the action begins.


**`ArrowVolleyCoordinator._flight_for` reads the shot's own compiled window
directly** (`OutcomeSchedule` assigns both `launch_at` and `arrive_at` per
entry), never recovering a launch delay by subtracting a constant from
`arrival_time` — a second number there could drift from the schedule and desync
an arrow's touchdown from its own damage. Any test pinning a VFX/domain timing
relationship must instantiate the `.tscn`: an export mistuned in a scene is
invisible to a subject built with `.new()`.

`RangedAttackPlan.get_firing_schedule()` produces the explicit firing list
`[(firing_node, target)]`: the order is authored into the list, no live-topology
read sits in the command path, and the volley is self-describing on the wire.

---

## Open forks

- `PresentationTempo.volley_stagger_span` and `volley_flight_time` values —
  feel, needs the real game; tuned on the authored `.tres`
  (`shared_default()`'s backing resource), never as a code constant. The one
  fixed constraint is `volley_flight_time > volley_stagger_span` — a house rule
  on the resource, not a pinned pair of numbers.
- `volley_draw_time` values, and the melee analogue of a preparatory phase.
