# The attack timeline contract

**Decided 2026-08-20**, out of the #488 discussion. This is what every attack
mode is being built *towards* — a single contract all three modes fulfil, so
that adding a fourth mode, or an on-hit effect, or an ammo type, is a matter of
satisfying a written spec rather than re-deriving what "when does this happen"
means from three different code paths.

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

**This is the AUTHORITY's timeline** (#511). Under
[multiplayer-sync-model.md](multiplayer-sync-model.md) the host runs exactly
what is written here — resolve, then `OutcomeApplier`, with every mode's
land-time gate live against the real world. A *peer* does not: it receives
`AttackRecord`, a post-apply record of what each landing actually did, and
replays those deltas through the same applier loop. It re-runs no gate,
re-reads no live offense, and computes no combat number, because it cannot —
mitigation is node-local, an earlier beat's cascade changes what a later beat
lands on, and a target may sit under fog it knows nothing about. Every
"re-read at land time" sentence below describes host-side behaviour. Nothing
about the host contract changes; the qualifier exists so a peer path is never
built by reading this as universal.

Two halves, both load-bearing:

- **Resolution is still up-front, and since #536 it is no longer *pure*.** It
  produces an `AttackOutcome` that has **already landed** in the `CombatWorld`
  it was handed — a result, not a plan of landings. What makes it safe as a
  preview, as AI scoring input and as #458's wire payload is not that it
  mutates nothing, but that the thing it mutates is a throwaway shadow (see
  "The world is ALWAYS a shadow" below). Read that section before writing code
  against `resolve()`; the rest of this page describes the timeline the
  landings run on either way.
- **Application is staged and live.** Each landing's *gate* — "is this target
  still allocated? still hostile? is this blade vertex still alive?" — is
  re-checked at the moment the landing applies, not at the moment it was
  planned.

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
| **Resolve** | `AttackPlan.resolve()`, once, at launch | Pure. Snapshots the *candidate set* and the attacker-side arithmetic. Emits `AttackOutcome`. |
| **Land** | per landing, in `arrival_time` order | Live. Gate re-check, then mitigation, then mutation, then any cascade — all synchronous within the beat. |

## What is read at which clock

The target state. Where this differs from what the code does today, the
"today" column says so — those gaps are the work.

| Input | Clock | Today |
|---|---|---|
| Candidate landing set (which nodes *could* be hit) | **Resolve** | ✅ all three modes |
| Ordering of landings | **Resolve** (authored into `arrival_time`) | ✅ all three modes stamp a real `arrival_time`; `OutcomeApplier` sorts on it (#499) |
| Landing gate (target still allocated / still hostile / vertex still alive) | **Land** | ✅ all three modes (#501 / #502 / #503) |
| Attacker offense (`ranged_damage`, blade vertex damage, spell damage) | **Commit** | ✅ all three modes — snapshotted, see below |
| Crit *decision* (`crit_chance` roll, `SpellDef.crit_conditions`) | **Resolve** | ✅ all three modes, one shared `CritRoll` (#507) — see below |
| Crit *multiplier* (`amount ×= crit_multiplier`) | **Land** | ✅ all three modes, in base `DamageInstance`/`HealInstance.land_on` |
| Defender mitigation (`armor`, `min_damage_taken`) | **Land** | ✅ already live — `Mitigation.apply` runs inside `SkillNode.take_damage` |
| Cascade / dealloc / entity death | **Land** | ✅ already live and synchronous |

### Offense is snapshotted at commit time — settled 2026-08-23

This doc used to say the split was **defence live, offence frozen**, that it had
"no principle behind it", and that the fix was to read offense at land time in
all three modes. **That was wrong, and #503 shipped the wrong half of it.** The
owner ruled the other way, and the three modes turn out to have been telling the
same story all along:

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

So the contract is **set frozen, offense frozen, defence live**:

| | Clock | Because |
|---|---|---|
| Candidate set | Commit | resolution must not discover targets |
| Attacker offense | Commit | the projectile / blade / spell carries what it left with |
| Landing gate | Land | the world it arrives in decides whether it arrives at all |
| Defender mitigation, cascade | Land | that is the defender's live state, not the attacker's |

**Nothing is lost by freezing offense, and that is the load-bearing half of the
argument.** The case that motivated a live read — a volley whose early arrows
already killed the target, so the late ones "should" recompute — is handled by
the **gate**, which vetoes them entirely. A stale number on an arrow that never
lands is not an error. Where the gate lets a hit through, the target is still
there and the attacker's own launch-time strength is the honest number.

Each mode's snapshot point, concretely:

- **Ranged** — `RangedDamageFormula.compute`, once per scheduled shot, all of
  them before any landing. Its `_read_offense` is the only read; #503's
  land-time re-read in `RangedHitInstance.land_on` was deleted.
- **Melee** — `MeleeAttackPlan.build_blade_state()` stamps
  `vertex_damage[i]` from each source node's `blade_damage`. Forge, then swing.
- **Magic** — `SpellResolver.impact_damage`, once at cast. It has a second,
  independent reason to freeze, stated at that function: a per-hop re-read would
  compound INT (INT² by hop 2).

**Ranged's freeze rests on a relationship between two authored numbers**, and
it is pinned rather than commented (`test_ranged_damage_formula.gd`):
`PresentationTempo.volley_flight_time` **must stay greater than**
`volley_stagger_span`, so the last arrow launches before the first one lands.
Retune `volley_stagger_span` above `volley_flight_time` on the authored
`.tres` and an arrow would be loosed *after* an earlier arrow had already
cascaded the board — at which point "snapshot at launch" and "snapshot at
resolve" stop being the same thing, silently, with no test failing and damage
merely going stale. (Since #543 these two live on `PresentationTempo`, not as
`const`s on `RangedDamageFormula` — see "The ranged volley ramp" below.)

### The crit split — the one input that spans two clocks

Crit (#507) is the only row above that appears twice, and the reason is worth
recording because the obvious "just do it at land, like mitigation" is wrong
in a way that is invisible until you look at the VFX layer.

- **The decision cannot wait for land.** `MagicBounceCoordinator` stamps
  `Projectile.crit_tier` when it *spawns* a bolt, and `Projectile` fires
  `_on_crit` at flight start — both strictly before the applier lands that
  wave. Deciding at land makes every magic projectile read tier 0. Magic's
  `SpellDef.crit_conditions` are resolve-bound anyway: they read `CastSpell`
  propagation state (predecessor, incident count) that exists nowhere else.
- **The multiply still happens at land**, in base
  `DamageInstance`/`HealInstance.land_on`. The original reason was that
  `RangedHitInstance.land_on` overwrote `amount` with a live `ranged_damage`
  read, discarding anything resolve had multiplied in — that read is gone as of
  2026-08-23 (above), so the surviving reason is narrower and worth stating:
  **a gated hit must not carry a multiplied amount.** A veto returns before
  `super.land_on`, so a dud's `amount` stays exactly what was loosed rather
  than a crit-inflated number no one ever took. That is also how the property
  is now pinned, since with offense frozen the two clocks are otherwise
  indistinguishable on a hit that lands.

So the decision is frozen with the candidate set and the multiply is applied
at land. The residual cost
is stated plainly: `crit_chance` / `crit_multiplier` are read at resolve, so a
mid-attack change to either is not seen by hits already in flight.

One further constraint falls out of a single seeded stream serving a whole
attack: **draws are consumed in `arrival_time` order.** `CritRoll.decide_all`
reuses `OutcomeApplier.in_arrival_order` rather than sorting again, so the two
cannot drift apart — and the symptom if they did would be crits that stop
reproducing under a replayed seed, not a visible break.

## Per-mode contract

Every mode must satisfy all four. The *mechanism* differs; the contract does
not.

1. **Emit candidates in time order**, each stamped with a real
   `HitInstance.arrival_time` in seconds from launch.
2. **Re-evaluate ownership and liveness at land time**, per landing.
3. **Snapshot attacker offense at commit time**, and never re-read it at land
   (see "Offense is snapshotted at commit time" above — this item said the
   opposite until 2026-08-23).
4. **Resolve against a substrate** (below), so AI and preview never mutate the
   real world.

### Magic

The seam already exists. `SpellResolver`'s `while not wave.is_empty()` loop is
literally the wave model above. The change is to move application *inside* it:

```
reduce incidents  →  on-hit effects  →  APPLY  →  expand next wave
```

so `config.filter.allows` and `max_visits_per_node` see post-apply ownership.
This is the smallest of the three changes and it delivers the fireball story
directly.

`PropagationEvent.beat` × a per-wave interval is where magic's `arrival_time`
comes from.

### Melee

**Do not interleave application into `BladeHitScan.scan`.** Its
`PhysicsShapeQueryParameters2D.exclude` is built once, before the substep loop;
interleaving would mean rebuilding the exclude list every substep of a 1.2s
sim, and the scan's purity (`ai_blade_rollout.gd` runs it on
`WorkerThreadPool`) is worth more than that.

Instead, **move the ownership filter from query time to consumption time**:

- `MeleeAttackPlan.collect_target_excludes()` currently excludes
  `not sn.is_allocated()` from the physics query. Stop excluding on that
  basis — keep excluding only the attacker's own nodes and the blade members.
- The applier walks `BladeHitEvent`s in `t` order and re-checks
  `is_allocated()` / `owned_by` / spike-pop per event.

`BladePopResolver.resolve()` already gates on `node.is_allocated()` and
`node.owned_by == attacker`. **Those predicates are already written as
live-state checks** — they simply never get re-evaluated, because `resolve()`
completes before a single point of damage lands. This change is what makes them
do the job they were written for.

`BladeHitEvent.t` is melee's `arrival_time`.

### Ranged

The degenerate case: candidates sorted by `arrival_time`, gate re-checked per
landing, damage snapshotted at launch and never re-read. Plus the volley ramp,
below.

---

## The substrate seam

> **Settled by #536: every resolution runs on a shadow, for every mode.** The
> asymmetry below is still the reason magic *forced* the issue, and worth
> reading for that — but the answer it reaches ("live slice for the cast, shadow
> for the tooltip") was superseded by the owner on 2026-08-23 in favour of
> *shadow always*. See "The world is ALWAYS a shadow" below for why that deletes
> the double-apply problem instead of managing it.

**A real melee or ranged attack does not need a substrate. A real magic attack
does.** The original framing of #498 — substrate first, it gates everything —
was wrong; the correction that replaced it ("nothing needs a substrate") then
over-generalised from melee to all three modes. The truth is an asymmetry, and
it turns on **where each mode's gate lives**.

- **Melee and ranged gate at *consumption* time.** The applier walks landings in
  order and re-reads `is_allocated()` / `owned_by` per landing. That is an
  ordinary read of the live world at the right moment; nothing is copied, and
  both moves are unblocked today.
- **Magic gates in *candidate selection*, which lives inside
  `SpellResolver.resolve()`.** For wave N+1's filter to see wave N's kill,
  `resolve()` itself must mutate. Two things then break: `OutcomeApplier.apply`
  (called once, `systems/battle_system.gd:256`) lands every hit a **second**
  time on a real cast, and `resolve()`'s dozen preview callers — spell tooltip,
  balance harness, the AI's magic candidates, tests — would mutate the live world
  just by being asked what a spell *would* do.

  A resolve-scoped ledger of "nodes this cast already killed", consulted ahead of
  real `owned_by`, is not an escape: that is a second implementation of
  ownership, and it is ruled out for the same reason as everything else here.

  So magic's wave-loop move is the first real consumer of `resolve_against`.
  Found while executing #501; see its comment of 2026-08-20. **Both breakages
  above are gone under shadow-always** — the second apply cannot happen because
  resolution never touches the world `OutcomeApplier` lands in, and the preview
  callers were never the special case, they were the general one.

What the substrate is for is narrower:

> **AI scoring and previews must not mutate.** Today `resolve()` already gates
> (`BladePopResolver`, propagation filters) against live state at resolve time,
> for free, because nothing has mutated yet. Once gating moves to *apply* time,
> the AI loses that accuracy unless it can run the applier — and it cannot run
> the applier against the real world.

So the substrate is a **follow-on that restores AI/preview accuracy**, not a
prerequisite. #536 delivered exactly that, and for free: since `resolve_against`
lands its outcome, an AI candidate's `thinned_nodes`, kill list and
post-mitigation numbers now come out of the real applier run against a detached
copy, not out of a parallel estimate. Melee's `BladePopResolver.resolve` — the
up-front batch pass that *was* that parallel estimate, and disagreed with the
live gate about a vertex that disintegrates before it pops — was deleted.

### How wrong is an un-simulated estimate? Badly, and non-uniformly

The tempting cheap answer is "the gate only ever *vetoes* landings, so an
ungated estimate is a strict upper bound — directional, bounded, discountable."
**It is not discountable.**

A propagating spell with escalating per-hop damage, seeded at a local degree
maximum, estimates `1 + 2 + 4 + … + 1024` while the real cast stops after ~20
damage, because the nodes it needed to bounce through are dead and no longer
valid candidates. The error scales with hop count and degree — *exactly where
the AI thinks the value is* — so it generates rank inversions rather than a
uniform offset. An AI using it reliably picks the worst spell target on the
board and scores it highest.

### The design: split state from notification

Split every mutation site into **state change** (moves to a plain `RefCounted`)
and **notification** (stays on the Node). Simulation runs the state half
against a throwaway copy. One implementation of the logic, so sim/real
agreement is a fact rather than a discipline.

```
SkillNode (Area2D)                    NodeCombat (RefCounted)
├── visuals, collision, addons        ├── board: NodeStatBoard   ← Resource, duplicated
├── signals, Events, presentation     ├── owner: EntityCombat
└── _combat ──────────────────────────┤ host: SkillNode  (null on a shadow)
                                      └── take_damage / heal / is_allocated
```

`SkillNode` *composes* its `NodeCombat` — it does not copy one, it owns the
live one. A shadow has `host == null`, so the notification branch does not
exist for it. **There is no "simulation in progress" mute flag**, and there
should not be: a flag is something you can fail to set; a null host is
something that cannot be reached.

Two facts make this small. `StatBoard` / `NodeStatBoard` already extend
`Resource` and are deep-duplicable — `_init_node_board()` does
`source.duplicate(true)` today — so the stat system does not move at all. And
`_node_board_ready` is lazy, driven from every write path rather than
`_ready()`, so a detached slice initialises correctly with no scene tree.

Full architecture, the `host` invariant, and the migration order are in #498.

### Why cloning SkillNodes was the wrong answer

Worth recording, because it is the obvious first idea. `duplicate()`-ing nodes
and running the real `take_damage` against the copies leaks through the global
broadcast surface: `Events.skill_node_damaged.emit(…)`, and
`owned_by.dispatch(…)` — a duplicated node's `owned_by` still points at the
**real** `Entity`. `AllocationSystem.force_deallocate` is the same, via
`_revoke_node_effects(node, previous)` and
`previous.navigator.mirror_remove(node)`.

Cloning the *Entity* as well closes the `owned_by` half. What it cannot close
is the bus: `LootSystem` connects to global `Events.entity_dying`
(`loot_system.gd:170`) and resolves the killer as
`turn_manager.current_entity`, so a simulated kill grants **real XP** and
spawns a real `SkillDustAddon` no matter whose clone died. Cloning entity
subtrees remains a viable cheaper fallback — bounded failure mode, a wrong
score rather than a broken world — but its cost is Node duplication per
rollout, which scales badly against exactly the many-rollout spell AI that
motivates the work.

This is also the honest answer to *"how do games like Monster Train do it?"* —
card battlers clone their battle state freely because that state is **plain
data with no engine objects and no global emit surface**. The reason cloning is
cheap there and not here is not object size; it is that their mutation path has
no reach outside the state object.

### The landing half shipped as `CombatWorld` (#498 step 3, #520)

`resolve_against(slice)` turned out to name two separable things, and the
second one is already done.

Because #501/#502/#503 had **already moved every gate and all arithmetic to
land time**, "resolve against a slice" for the *landing* half is just: run the
same `OutcomeApplier` loop, the same per-mode gates, the same mitigation, but
look each target's state up somewhere else. That lookup is `CombatWorld`
(`combat/combat_world.gd`):

```
record replay (every machine): OutcomeApplier.apply(outcome, CombatWorld.live(),  clock)
resolution, always:            OutcomeApplier.apply(outcome, CombatWorld.shadow(), clock)
```

**The world is a required parameter, never a defaulted one** (owner call
2026-08-23). A `world = null` meaning "live" would put an implicit live branch
back inside `OutcomeApplier` — the exact shape #498 exists to delete, and the
thing that turns *"the sim and the real path agree by construction"* back into
*"by discipline"*. Same rule on `BladePopResolver.LiveGate.admit`. Naming the
world at the call site costs eleven lines repo-wide.

`HitInstance.land_on(node: NodeCombat, world: CombatWorld)` — the hit's
`target` stays a real `SkillNode`, because that is its **identity** (what a
record serializes, what a fogged peer resolves by `stable_id`, what every VFX
observer reads). Only the **state** it mutates is swappable, and the swap is
one dictionary lookup. There is no preview flag anywhere in the chain.

A shadow world grows on demand: the first hit on a node whose owner is not yet
snapshotted snapshots that owner's *whole* owned subgraph then. Late is the
same as up front, because a shadow resolve never writes to the real world — so
the real world is frozen for its whole duration — and it means only the
entities an attack actually touches are paid for.

**No shared shadow `GraphMirror` is needed, and that rests on one assumption.**
Topology never changes mid-attack, so islanding and propagation keep walking the
*real* graph; only ownership and stats route through the slice. That assumption
is now pinned by test (`test_a_full_shadow_resolve_changes_no_topology`) rather
than by comment: a future displacement or terraform mechanic that severs or adds
an edge mid-cascade would otherwise corrupt shadow propagation silently, with
nothing else in the suite positioned to notice. It is the same standing
assumption melee's physics exemption already relies on.

### The candidate-set half shipped as `resolve_against(world)` (#536)

The other half was magic's alone, and it closed the same way it was predicted
to: `SpellResolver` **lands each wave before expanding the next one**, so
`config.filter.allows(...)` on wave N+1 selects against a world in which wave
N's kills have already happened. Melee and ranged needed nothing structural —
their candidate sets were always allowed to freeze at resolve, and their gates
already ran at land time against whichever world they were handed.

Two things had to move together, and only the first is obvious:

1. **The wave loop lands.** Between "reduce incidents" and "expand next wave",
   the wave's hits go through `OutcomeApplier.land_one` — the *same* landing
   every other path uses, extracted from `apply`'s loop so there is exactly one
   implementation of "land a hit".
2. **The filters ask the world, not the node.** A hit's target stays the real
   `SkillNode` (it is identity), so `to.ownership_bit(caster)` reads a node that
   is *still alive* no matter what the resolver did. `PropagationContext.world`
   is where the question goes now, via `ownership_bit_of` / `is_allocated_in_world`;
   `OwnerFilter` and `ExpressionFilter` are the two callers. Landing without
   this changes nothing observable — that was the bug behind the bug.

Magic's crit roll moved with it, from one `CritRoll.decide_all` after the walk
to a per-wave `decide` before each wave lands. The draw sequence is unchanged
(`decide_all` iterated arrival order, which for magic *is* wave order with an
index-stable tiebreak); it had to move because `CritRoll.apply` multiplies at
land time and cannot multiply by a decision not yet made.

**`resolve_against(world)` returns an outcome already landed in `world`.** That
is the contract for all three modes. `resolve()` is the convenience that mints a
throwaway shadow, resolves, and frees it — which is what every preview, tooltip
and AI rollout calls.

### The world is ALWAYS a shadow, and the host replays itself (#536)

Owner call, 2026-08-23: *"shadow always."*

```
authority: resolve on a shadow -> capture the AttackRecord -> confirm/broadcast
every machine, authority included: rebuild that record -> land it on the BeatClock
```

`BattleSystem` has one launch path. The payload still decides which half runs —
an empty record means "nobody has computed this yet" — but there is no longer a
version of the apply step for the machine that computed it. Per #498: *the host
becomes a peer of itself; it is the only one that computes, not the only one
that replays.*

**Why shadow-always rather than "live for a real cast".** Magic gates during
candidate selection, so `resolve` must mutate. If it mutated the real world,
`OutcomeApplier` would then land every hit a second time and the special case
would have to be detected and suppressed — the shape #501's correction warned
about. With shadow-always there is nothing to suppress: `OutcomeApplier`
against `CombatWorld.live()` remains the sole mutator of the real world, and the
only thing it ever lands there is a rebuilt record.

**The capture → rebuild round trip is load-bearing, not waste.** Every land-time
write is one-shot: `CritRoll.apply` multiplies `amount` in place, `hp_before` /
`hp_after` get overwritten, and a `HitInstance.deallocations` left over from the
shadow would make `BattleSystem._on_node_depleted` take its *recorded* branch and
re-apply a stale cascade set. Rebuilding mints fresh hits, so none of that is
possible by construction. Do not optimise it away.

**One consequence worth naming: an announcement made during resolution has no
audience.** The melee spike-pop cue used to be emitted by
`BladePopResolver.LiveGate` as it popped; the gate now runs on the authority's
shadow, so it *records* the pop on `HitInstance.popped_vertex` instead, the
record carries it, and `OutcomeApplier.land_one` emits it as the hit lands. Same
beat as before (#504's requirement), and a peer now gets the cue too — the
animation-replay emitter this descends from could only ever fire on the machine
that swung. Any future in-resolution announcement needs the same treatment.

### `AttackOutcome` is the result, not a plan

Under this model `resolve()` becomes `resolve_against(world)` — a throwaway
shadow for a preview, the authority's own shadow for a launch. Same function,
same code path, and never the real world.

- **`AttackPlan` holds the inputs.** Change one and the outcome is recomputable.
- **`AttackOutcome` is *the* deterministic result** of those inputs, computable
  at any time.

`HitInstance.effective_amount`'s *"0.0 until applied"* caveat disappears — it
is always filled, because resolving **is** applying, to a world you may throw
away. Totals, per-node damage, kill lists and the enemy/friendly healing split
are then accessors over `outcome.hits`, not new machinery. XP is the one
exception: it lives in `LootSystem`, which gains a pure `preview_kill_xp` query
that its own granting path also calls.

### What the shadow must copy

A revocation ledger is **not sufficient**, and this is the trap (closed in
#520 — a shadow now re-runs `recompute`; see below):

`AuraEffect._on_node_deallocated` calls `recompute(ctx)`, which does
`ctx.revoke_all()` and then **re-derives every modifier from the current
world** (`effects/aura_effect.gd:59-74`). It is a full rebuild, not a revoke.
The net effect during an attack is still monotone-shrinking in practice (nodes
only ever leave ownership mid-attack), but a ledger that only records
revocations cannot reproduce a rebuild, and any distance-scaled aura recomputes
its *values*, not merely its membership.

So the shadow is a real copy of:

- **every affected entity's complete owned subgraph** — HP and ownership per
  node
- those entities' stat boards
- **magic only:** unallocated nodes within the spell's hop reach, which exist
  purely as propagation conduits for spells whose filter admits them

with the effect hooks able to run against it. Far cheaper than a world clone —
no scene tree, no addons-as-children, no physics — but not free, and not a
ledger.

**How the hooks run against it (#520).** `EffectContext` is addressed at an
`EntityCombat`, not an `Entity` — its public API is unchanged, so no `Effect`
implementer knows the difference, and the same `AuraEffect.recompute` rebuilds
against a shadow board when handed a shadow slice. `EntityCombat` therefore
carries the shadow's stand-ins for everything the live `Entity` owned: the
effect ledger (`EffectInstance.clone_for` — rows copied, live handles kept,
because `StatBoard._localized` translates them), the tag store, and the mirror
an aura measures over. `apply_cascade`'s shadow branch does what
`force_deallocate` does, in its order: revoke sweep, ownership, then dispatch
`_on_node_deallocated` — and it is that last step which makes wave N+1 read
post-cascade armour.

Two rules that fall out, and both are load-bearing:

- **A shadow reads the pure halves, never the mutating helpers.**
  `SkillNode.remove_entity_modifiers_from` erases `_scaled_sets` on the *real*
  node while it works. So the question ("what does this node grant") is split
  from the verb ("un-grant it"): `granted_entity_modifiers()` /
  `scaled_effect_leaves()` are pure, both worlds share them, and the erase
  stays on the live path.
- **A shadow slice never falls back to the live world for a node lookup.**
  That fallback is precisely how an aura recomputing on a shadow would grant
  node-local modifiers to real nodes. A bare `EntityCombat.snapshot()` mints a
  private `CombatWorld` and frees it with itself.

**Do not reach-bound the owned subgraph.** The obvious optimisation — copy only
nodes the attack can physically touch — computes the wrong cascade.
`BattleSystem._on_node_depleted` calls
`defender.navigator.nodes_islanded_by_removing(node, defender.core_location)`,
which walks the defender's *entire* territory to find what islands when a node
leaves. A node fifty hops from the impact can be part of the cascade. Unowned
nodes are the ones that can be skipped, and only because their sole gameplay
function is to be a spell conduit.

### The one thing a shadow cannot hold

Melee's hit detection is a **physics query against the real world**
(`space_state.intersect_shape`). A shadow cannot hold collision shapes.

This is fine, because **nothing moves nodes mid-attack**: scan once against the
real world for geometry, and shadow only the gate re-evaluation. If a future
mechanic ever displaces a node during a swing, this assumption breaks and the
melee substrate story needs revisiting.

---

## Ordering and `arrival_time`

### `arrival_time` is not optional

`HitInstance.arrival_time` is currently set **only** by
`RangedDamageFormula` — every melee and magic hit carries `0.0`, documented as
"0.0 for hit types that don't yet compute one."

That is a semantic lie (they do not land at t=0) and under a design where the
world mutates on the reveal clock it is worse than cosmetic: with
`arrival_time == 0`, every melee hit and every spell hop mutates
simultaneously, and the whole staged model degenerates to today's behaviour for
two of three modes. #488 lists stamping it uniformly as *"optional, last"*;
under this contract it is a **prerequisite**, not a nicety.

### The ranged volley ramp

Allocation order must never influence a combat outcome. Today it does: the
firing order is `GraphMirror._node_ids` insertion order, which is allocation
order. It is *deterministic across peers* (same command replay → same
allocation order), so it is not a desync — it is a design bug, and a worse one
than randomness, because a player could learn to exploit it.

**Author the schedule; derive nothing from iteration order.**

```
rank reaching leaves by euclidean distance to target, ascending
    tie-break: SkillNode.stable_id          # wire-legal, minted by Graph
d_min, d_max   = distance of the first and last ranked leaf
frac_i         = (d_i - d_min) / (d_max - d_min)   # 0 .. 1; 0 if the span is 0
```

**Since #543 that is the whole of what `RangedAttackPlan.resolve_against`
records about timing.** `frac_i` is stamped onto `HitInstance.structural_key`
— the resolver emits structure, never seconds. Turning it into a clock is
`OutcomeSchedule.compile`'s job, in its `Cadence.RAMP` branch, off the
authored `PresentationTempo`:

```
launch_time_i  = volley_draw_time + frac_i * volley_stagger_span
arrival_time_i = launch_time_i + volley_flight_time   # constant, NOT distance/speed
```

so a slow-motion replay (a lower `combat_time_scale`) stretches the compiled
schedule instead of the resolver re-authoring one.

**The ramp is metric, not ordinal.** Settled 2026-08-21. It used to lerp on
`rank_i / (n - 1)`, which spaced every shot evenly no matter where the leaves
actually stood: two leaves 0.1px apart launched a full `1/(n-1)` slice apart,
and a lone far outlier was just "the last rank". Normalizing on *distance*
instead means a clustered firing line looses as one salvo and an outlier owns
the whole tail of the window — the volley's rhythm now reads the shape of your
territory. `d_max = d_min` (n == 1, or perfectly equidistant leaves) is a
degenerate span, guarded exactly, not approximately: everyone fires on the
same beat.

This is not a retreat from the rule above — distance is pure geometry off
`global_position`, so allocation order still cannot touch it, and ties are
still broken by `stable_id` in the ranking, which `OutcomeApplier`'s stable
`(arrival_time, original_index)` sort then preserves through equal
`arrival_time`s.

**Flight time is a constant, not `distance / PROJECTILE_SPEED`.** Settled
2026-08-20. The fiction is the arc: a point-blank shot is lobbed nearly
straight up, a distant one goes nearly flat, and both take about the same time
to come down. Arrows are *aimed*, not fired on a rail.

Mechanically this is the stronger choice, which is why it wins:

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
  visibly draw before loosing. **0.0 for now**, but it is authored in from the
  start so it can be turned on without re-deriving the schedule. Melee wants an
  analogous preparatory phase.
- **`t = 0` is the start of the draw**, not the first arrival. Every
  `arrival_time` is measured from the moment the action begins.

**`ArrowVolleyCoordinator._flight_for` reads the shot's own compiled window
directly**, rather than recovering a launch delay by subtracting a constant
from `arrival_time` — the compiler (`OutcomeSchedule`) already assigns both
`launch_at` and `arrive_at` per entry, so there is no second number here that
could drift from it (#543). Before that, the coordinator's `shot_flight_time`
export re-derived a launch delay from `arrival_time`, and a mistuned export
desynced the arrow's touchdown from its own damage — biting in the shipped
scene (`flight_time = 2.0` → a 0.8s floor against a 0.35s airtime, every arrow
landing 0.45s after its damage) while `test_arrow_volley_coordinator.gd`
stayed green by constructing the coordinator in code and reading the code
default instead of the scene's.

**Watch:** that is exactly the drift class #479/#481 cost five rounds of
latches, so the replacement test instantiates the `.tscn`. Any test pinning a
VFX/domain timing relationship must do the same — an export mistuned in a
scene is invisible to a subject built with `.new()`.

### Explicit firing list

`RangedAttackPlan` should produce `[(firing_node, target)]` explicitly, today,
with no firing-group UI. It costs nothing, removes a live-topology read from
the command path, makes the volley self-describing on the wire, and **subsumes
the ordering fix** — the order is authored into the list rather than emergent.

Firing groups (#495/#496's volley composer) are then a UI on top of a payload
that already exists.

---

## What this corrects

**`melee_attack_plan.gd:380-386` and `melee_preview.gd`'s `launch()` docstring**
argue that a post-cascade rescan "would exclude nodes the cascade just
deallocated, silently dropping hits/pops the pre-cascade `resolve()` correctly
saw." That is **valid for what it rejected and invalid as a principle.**

What it rejected: `MeleePreview` re-scanning to *animate an outcome that had
already fully landed*. Dropping hits there desyncs the animation from applied
damage — a real bug about replaying a finished mutation.

What it does not license: freezing the gate. Under this contract the deallocated
arm *should* drop out, because the damage has not landed yet when the gate is
checked. The comments need rewording when melee moves over, or the next agent
will read them as forbidding the thing we are building.

**`docs/domain/multiplayer-sync-model.md`** says
`MeleeAttackPlan.resolve()` "is not safely re-simulable" because
`BladePopResolver` resolves pops during the scan. #488's decision comment
establishes this is wrong — `BladeSim` is a pure fixed-dt loop and
order-dependence *inside* a deterministic function is not a divergence risk.
That doc needs the correction independently of this one.

## Open forks

- `PresentationTempo.volley_stagger_span` and `volley_flight_time` values —
  feel, needs the real game; tuned on the authored `.tres`
  (`shared_default()`'s backing resource), never as a code constant. The one
  fixed constraint is `volley_flight_time > volley_stagger_span` (see "Offense
  is snapshotted at commit time" above) — a house rule on the resource, not a
  pinned pair of numbers.
- `volley_draw_time` values, and the melee analogue of a preparatory phase.
- ~~Whether the combat slice (#498) is worth its size~~ — **settled.** The owner
  call of 2026-08-21 made it a networking requirement, not an optimisation: a
  fogged client cannot walk the nodes a spell bounces through, so propagation
  has to arrive as data. The landing half shipped as `CombatWorld` (#498 step
  3), the revocation half as #520, and the candidate-set half — magic's wave
  loop, plus the collapse of the two launch paths — as #536. Step 3 is closed;
  see the two sections above.
- **Where the notification half sends its presentation call.** Master runs
  design A (`RevealRecorder` live, `shown_hp`/`shown_owner` on `SkillNode`)
  while #488's decision comment specifies design B (the world mutates on the
  reveal clock, no view store). #494 owns resolving that. The state/notification
  split is **orthogonal** to it — under A the notification half calls
  `RevealRecorder`, under B it just emits — so #498 must not be written as
  though either has won.
