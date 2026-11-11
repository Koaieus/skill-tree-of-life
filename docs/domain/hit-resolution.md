# Hit resolution — one hit from landing to applied

What *is*: how one hit an attack resolved reaches the world — the landing that
mints it, the applier that walks it, the beat it lands in, mitigation, crit,
a status landing, and today's only go-off. The clocks (what is read at commit,
resolve and land) and the per-mode contract stay in
[attack-timeline.md](attack-timeline.md); the shadow/live state split is
[entity-combat.md](entity-combat.md); status rows, spill and the sandpile are
[status-effects.md](status-effects.md); the defence axes a hit meets are
[defense-axes.md](defense-axes.md). The elements drop (#1716) changes much of
this page: each section it changes carries one `changing:` line naming the
child issue and its file in the design record: [`docs/design/elements.md`](../design/elements.md).

## The pieces: `HitLanding` and the `HitInstance` kinds

changing: a head mark and the head's load, #1798; see docs/design/elements/hit-resolution.md

A **hit** is one `HitInstance` (`attack/outcome/hit_instance.gd`): one landing's
effect on one target node, held in `AttackOutcome.hits`. `target` is the hit's
identity (what a record ships and a peer resolves by `stable_id`); the state it
mutates is whatever `NodeCombat` the world hands `land_on`. `HitInstance.kind`
routes the reveal and the record; the enum is appended last because the wire
carries `int(kind)`, and 3 is a retired value:

| `Kind` | Classes | Lands on |
|---|---|---|
| `DAMAGE` (0) | `DamageInstance`; `RangedHitInstance` (`attack/formulas/ranged_damage.gd`), `BladeDamageInstance` (`attack/melee/sim/`), `PairedDamageInstance`, `CleansePriceInstance` | `NodeCombat.take_damage`, through [Mitigation](#mitigation); a negative result flips the hit to `HEAL` |
| `HEAL` (1) | `HealInstance`, `PairedHealInstance` | `NodeCombat.heal_damage`; never mitigated, never reclassified |
| `STATUS` (2) | `StatusInstance` (plus private copies in `FluxEffect` and `MultiplyRowEffect`) | `NodeCombat.apply_status`, or the entity on a cracked core ([Statuses landing](#statuses-landing)) |
| `GATE_FLIP` (4) | `GateFlipInstance` | the topology: a melee fuse's gate flip (`land_flip(world, alloc)`) |
| `EXERT` (5) | `ExertInstance` | `StatusDef._on_exerted` on an origin-set node's rows |
| `CURE` (6) | `CureInstance` | a cleanse's per-status stack removal and the heal it buys |
| `ADDON_DESTROY` (7) | `AddonDestroyInstance` | the defender's Bunker addon (`land_destroy(world)`) |

Before a hit lands, `amount` may be a coefficient: `HitInstance.basis`
(`PERCENT_MAX`, `PERCENT_CURRENT`) and the blade's speed curve are resolved
into HP once in `land_on` (`resolve_amount` for a basis), and a rebuilt record carries
the flat number.

A **landing** is one `HitLanding` (`attack/outcome/hit_landing.gd`): the facts
every hit it emits shares — `attacker`, `source`, `origin`, `read_node`,
`target`, `structural_key`, `paired`, `hit_key` — what an `OnHitEffect` reads
whatever mode produced it ([ADR 0044](../adr/0044-one-on-hit-vocabulary-for-every-attack-mode.md)). A spell's landing is the
`LandingContext` subclass; an arrow's or a blade contact's is
`HitLanding.riding(primary, hits, gather_cache)`, which sets `paired` to the
primary hit, stamps the landing's `hit_key` on it, and takes `raw_amount` /
`raw_type` off it. Effects append through `emit(hit)` in authored order. A
hit an effect mints takes the eight shared facts in one call,
`landing.copy_facts_to(hit)`: `StatusInstance.stamp_landing` sets the def and
calls it, as do `DetonateEffect`'s cure and `PairedDamageEffect`'s share
(`HaulEffect` sets its own target, origin and source and does not). The
builder calls `place()` once the effects have run (below), which orders the
span and then runs the landing site's **`stamper`** callable over it,
`func(hit) -> void`: a spell's stamps the caster, its crit conditions and the
wave ordinal and files the hit on its timeline event; an arrow's stamps its
ammo id on every rider; a blade contact sets none. `SplashEffect._retargeted`
copies a landing whole, `stamper` included. The landing also carries
the per-compile `gather_cache`, the spell's `stack_scale` and the `detonated`
scope ([Go-off zero](#go-off-zero-explosive-detonation)).

A **rider** is any hit with `paired` set or a `land_mask`
([ADR 0049](../adr/0049-a-rider-is-any-hit-instance-gated-by-its-paired-hit-and-land-mask.md)): `rider_gated(node, world)` duds it iff its paired hit did
not land, or the receiving node's ownership bit to `attacker` misses
`land_mask` (not re-read on a rebuilt hit, `land_resolved`). `hit_key` is what
makes "the riders of arrow i" a set, read by key, never by position; Greed
spends once per key.

## The walk: `OutcomeApplier`

changing: stage one (the gather) runs per beat, #1798; see docs/design/elements/hit-resolution.md

`OutcomeApplier` (`attack/outcome/outcome_applier.gd`) is the one place an
`AttackOutcome` reaches a world, and `land_one` the only place a
`HitInstance.land_on` is called from.

- **`apply(outcome, world, clock, alloc)`** compiles a schedule if the outcome
  has none, then drains a `HitQueue` over `outcome.hits` with a fresh
  once-per-apply blast set.
- **`drain(queue, world, beat, alloc, crit_rng, announced)`** is the one
  landing loop, `apply`'s and a spell wave's. It takes the queue's hits in
  order, flushes the beat whenever `schedule_index` changes
  ([The beat](#the-beat)), awaits `beat.advance_to(hit.arrival_time)`, calls
  `land_one` with the queue, and announces a blast's `blast_mark` once per
  `announced` set on a live world (a wave passes none). One more flush ends
  it. On an instant clock it never parks, so `SpellResolver` calls it
  un-awaited over a queue of one wave's hits and the wave has landed when the
  call returns.
- **`HitQueue`** (`attack/outcome/hit_queue.gd`) is the open worklist.
  `HitQueue.over(hits, from)` orders `hits[from..]` by `in_arrival_order` and
  holds a cursor at the next hit to land. `push(hit)` appends to the record
  (the outcome's `hits`) and slots the hit into the unlanded tail after every
  unlanded hit of its own `schedule_index` and before the first greater one,
  never ahead of the cursor: a hit pushed at an index the drain has passed
  lands next. What the queue yields is the order the crit stream is drawn
  in. Nothing pushes yet; #1798's gather head is the first pusher.
- **`land_one(hit, world, alloc, crit_rng, queue)`** never awaits, which is
  why a wave can land mid-walk. `queue` is the worklist the landing drains
  from, null for a standalone landing (the spell's exert set); it is unread
  until a gather head dispatches on it (#1798). In order: a hit with
  recorded `deallocations` or `settle` is a rebuilt record's and feeds the
  beat (`feed_recorded`, `feed_settle`), any other is offered to `track_hit`;
  `ADDON_DESTROY` and `GATE_FLIP` branch to their own landers; a freed `target`
  or `origin` lands nothing; `world.combat_for(target)` picks the slice;
  `CritRoll.decide` draws iff a stream was handed in; `hit.land_on(slice,
  world)`; a fresh hit's `deallocations` are tracked for the flush; a live
  world emits the recorded `popped_vertex` cue.
- **`in_arrival_order(hits)`** sorts on `(schedule_index, original index)`,
  decorate-sort-undecorate, so ties keep list order. Never on
  `arrival_time`: seconds differ per peer with tempo, the structural index
  does not (#543 D2). It is also the order the crit stream is drawn in.

### `OutcomeApplier.apply`: the parameters

`OutcomeApplier.apply(outcome, world, clock, alloc)` lands every hit in
schedule order ([attack-timeline.md](attack-timeline.md) § "Ordering and `arrival_time`"). Per-mode ramps (ranged's
rank-authored schedule, magic's propagation beat, melee's `BladeHitEvent.t`) are
what make that order meaningful.

- **Order is the schedule's structure; the wait is its seconds.** The sort keys
  off `HitInstance.schedule_index`, which every machine derives identically from
  the same structure; the wait reads seconds no two machines need to agree on.
  That separation is what lets tempo be per-peer. `apply` compiles a schedule
  when the outcome has none yet because a replayed record arrives with
  structure and no seconds, and exactly one place must turn one into the other.
- **The drain is the clock.** It waits out each hit's `arrival_time` on `clock`
  before landing it, so the world mutates when the arrow arrives and everything
  that draws reads the model on one clock, with no view store to keep in step.
  `BeatClock.instant_clock` (the default) lands the whole outcome synchronously;
  see `BeatClock` for why this is not frame-ordered mutation.
- **`alloc`** is read only by a `GateFlipInstance` landing on a live world (a
  melee fuse's real flip goes through `AllocationSystem.apply_gate_flip_recorded`).
  Null skips such a landing with a warning rather than flipping without the
  cascade.
- **`world` is required**, placed ahead of the optional `clock`. Live for a real
  launch or peer replay, shadow for resolution: the identical loop, gates and
  arithmetic run against detached slices, and there is no `is_preview` flag
  anywhere below
  ([ADR 0079](../adr/0079-resolution-always-runs-on-a-shadow-the-world-is-a-required-parameter.md)).

## Landing against a world: `CombatWorld`

changing: the live world runs the world turn's temperature flow and burn, #1795, #1805; see docs/design/elements/terrain.md

```
record replay (every machine): OutcomeApplier.apply(outcome, CombatWorld.live(),  clock)
resolution, always:            OutcomeApplier.apply(outcome, CombatWorld.shadow(), clock)
```

`combat/combat_world.gd` looks each target's state up somewhere else; the same
`OutcomeApplier` loop, per-mode gates and mitigation run in both. **The world is
a required parameter, never a defaulted one**
([ADR 0079](../adr/0079-resolution-always-runs-on-a-shadow-the-world-is-a-required-parameter.md));
same rule on `BladePopResolver.LiveGate.admit`.

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

One class rather than a per-entity slice: an attack, a propagating spell above
all, crosses territory of several entities and `EntityCombat.snapshot` is
per-entity, so the world holds as many entity slices as the attack touches plus
ownerless slices for unallocated conduit nodes, under one `SkillNode` ->
`NodeCombat` index. Laziness is what makes shadows cheap (the cost is paid per
entity actually hit and per node actually visited, rather than for the whole
owned subgraph per hover). Every shadow needs `free_shadow` for the reference
cycles `EntityCombat.free_shadow` documents; a live world holds and frees
nothing.

A live world also keeps a **terrain index** (#1794): an insertion-ordered set
of the live node slices with `t != 0` or `charge > 0`
(`note_terrain` / `forget_terrain` / `reindex_terrain` / `holds_terrain` /
`terrain_nodes`). `NodeCombat.add_terrain`, the one terrain writer, keeps it in
step and a `GraphSnapshot` decode rebuilds it per node; a shadow world refuses
it, since no shadow runs a world turn. Nothing reads it yet (#1795's pass will).

**No shared shadow `GraphMirror` is needed, and that rests on one assumption:**
topology never changes mid-attack, so islanding and propagation walk the *real*
graph while only ownership and stats route through the shadow. It is pinned by
`test_a_full_shadow_resolve_changes_no_topology`; a displacement or terraform
mechanic that severs or adds an edge mid-cascade would break it.

## A rider lands after its hit; a beat's aspect riders after all its damage

Why, and the shapes that lost: [ADR 0067](../adr/0067-a-status-rider-lands-before-its-paired-hit-and-the-hits-gate-is-a-memoized-step.md)
for the placement and the memoized gate (§2 to §4), and [ADR 0092](../adr/0092-within-a-beat-all-damage-lands-before-any-aspect-rider-so-the-ice-reads-the-floater-and-a-depleted-node-takes-no-aspect-riders.md)
for the order, which supersedes ADR 0067 §1 (a status rider used to land
before its hit and lift it).

- **Priority.** `HitInstance.land_priority()` returns `LandPriority.BEFORE`
  (−1), `PRIMARY` (0) or `AFTER` (1). Base: `AFTER` for a rider (`paired`
  set), else `PRIMARY`. `StatusInstance` returns `AFTER` when it rides a lead
  (`paired` set: an arrow's, a contact's) or is blast or splash shaped
  (`blast_mark`, `land_mask`), else `BEFORE`: a bare status (every magic
  status, an infusion's included) keeps its ADR 0067 list slot ahead of its
  landing's own block. Priority is list position only; an aspect rider's land
  turn is the drain's (below), so a bare status listed first still lands after
  its beat's damage, and only its order among the beat's aspect riders follows
  the list: an intake's stacks are on the row before the spell's own row
  operations read it (Gloomflux: the intake's add, then `MultiplyRowEffect`'s
  double).
- **Placement is list position, set once by the landing's builder.**
  `HitLanding.place()` reorders only the landing's span `hits[anchor..]`: the
  landing's own block `hits[anchor..lead)` in authored order, then `PRIMARY`,
  then `AFTER` — a stable partition, never a sort. The builders are `RangedDamageFormula.ride`, `SwingResolve` and
  `SpellResolver`. `in_arrival_order` never reads priority, so a rider never
  jumps another arrow's hit in a shared beat.
- **The beat order is `OutcomeApplier.drain`'s.** A beat is a run of equal
  `HitInstance.structural_key`: a magic wave (every hit stamped
  `float(hop_index)`), an arrow and its riders (`HitLanding.riding` copies the
  arrow's key), a melee contact and its riders (`t / swing_duration`). It is
  not a `schedule_index`, which ranged and melee compile one per hit. The
  queue yields `(schedule_index, list order)`, so a beat's hits are adjacent;
  `drain` lands them in that order except the aspect riders
  (`HitInstance.is_aspect_rider()`, true on every `StatusInstance`, a bare one
  included, except a status `ElementRoster.for_status` knows), which it holds and lands, in queue order, once the queue yields
  another key or runs dry. Every other hit of a beat lands before any of its
  aspect riders, each half in list order. `drain` is the one landing loop, so
  `apply` (live, shadow, every replay of a rebuilt `AttackRecord`) and the
  spell wave land in the same order. The hold is streamed, not an array
  partition, because the queue is open: a same-key hit `HitQueue.push`ed
  mid-beat still lands ahead of the held riders. A terrain rider (Heat, Cold,
  Charge) returns false: it is neither held nor dudded and lands in list order
  with the damage.
- **A depleted node takes no aspect rider.** "Depleted" is "stripped by this
  beat's hits", never "at 0 HP": a neutral or bare node at 0 HP takes its
  riders as before. `drain` collects, per beat, the non-core nodes in each
  landed hit's `deallocations` (the `DeallocEntry`s a kill writes onto its
  hit: the depleted node and any node its cascade cut off; a replay's are the
  record's), and sets `gated` on a held aspect rider whose target is one of
  them before landing it; `StatusInstance.land_on` then duds (power and
  amounts zeroed, like a gated rider), shipped as `AttackRecord.FLAG_GATED`.
  The set lives in `drain`, not on `CombatWorld`: the removal collector
  flushes per `schedule_index`, which splits an arrow from its own riders. A
  cracked core is not depleted (it is never stripped, `was_core` entries are
  skipped); its status falls through to the entity
  ([Statuses landing](#statuses-landing)). A terrain rider is never dudded.
- **The gate is memoized.** `resolve_gate(world)` decides a hit's veto once;
  the first asker decides it — the hit's own `land_on`, or a rider through
  `rider_gated`, which asks it first (only a hand-built list puts a rider
  ahead of its hit now). `landed()` reads the verdict (base: not
  `gated`; melee's unadmitted contact overrides it). `RangedHitInstance` runs
  its `passes_gate` there, `BladeDamageInstance` its `LiveGate.admit` with the
  spike pop and `popped_vertex`, so a pop happens once whichever lands first.
- **What follows:** a curse, sunder or mark rider lifts the hits of later
  beats, never its own hit or any hit of its own beat, so a hit reads the
  armor and floor as they stood when its beat began; a lead's crit is drawn
  before any of its riders land ([CritRoll](#critroll-the-one-crit-implementation)).

## The beat

changing: a beat lands in generations, each node read once per generation over all its arrivals, #1798; a Frozen node settles once per generation, #1807; see docs/design/elements/hit-resolution.md

A **beat** is the unit removals spill and piles settle in. Inside an attack it
is one `schedule_index` group of `OutcomeApplier.apply`; elsewhere it is one
dealloc command, one spell wave, one turn-end tick step, a gate-flip command
(the full list: [status-effects.md](status-effects.md) § "The status slice",
Spill).

- **The recording hit.** `CombatWorld.track_hit(hit)` keeps the first fresh
  landing since the last flush; the flush writes the beat's sandpile settle
  onto its `HitInstance.settle` as `CombatWorld.SettleOp`s. `track_entries`
  keeps the `DeallocEntry`s a fresh landing produced; the flush writes each
  computed spill transfer onto its sender's entry.
- **A recorded landing receives, never computes.** A rebuilt hit arrives with
  its `deallocations` / `settle` filled; `land_one` feeds them in, and the
  flush (`_land_recorded`) lands exactly those transfers and ops; removals the
  replay notes meanwhile are dropped uncomputed, and the piles they enqueued
  wait for the next computing flush.
- **`flush_removals()` ends the beat.** A computing beat loops: spill
  (`StatusSpread.on_removed` once per cause and row `(def.id, key)` over the
  beat's whole removed union, landed through `SpreadApplier`), then
  `settle_topples()`, until a settle round topples nothing; `settle_round_cap`
  (32) is a `push_error` alarm, not a rule. A re-entrant call returns at once.
  The killing hit's `DamageInstance.spill_scale` (`mark_spill_scale`) scales
  only the node it depleted.
- Live removals still pending at a turn hand-off are a bug:
  `TurnManager.end_turn` `push_error`s on `CombatWorld.has_pending_removals()`.

The spill rules and the sandpile's worklist: [status-effects.md](status-effects.md)
§ "The status slice" (Spill, Sandpile settle).

## Mitigation

changing: Frozen's damage breaker reads `Mitigation.compute` on each arrival, #1807; see docs/design/elements/frozen.md

`Mitigation.apply_to(raw, defender)` (`attack/formulas/mitigation.gd`) is the
door: `NodeCombat.take_damage` calls it for live and shadow slices alike and
turns "5 PHYSICAL" into the post-armor number that subtracts HP.
`Mitigation.apply(raw, skill_node)` wraps it for a node's live slice. The
incoming amount is rounded up to a whole number once, at the top of
`take_damage` and before mitigation (`HitPoints.whole`,
[ADR 0033](../adr/0033-damage-and-heal-magnitudes-round-up-once-where-produced-mitigation-stays-max-floor.md)), so armor and the floor, both whole, keep the result whole.

- `final = max(min_damage_taken, raw - effective_armor)`, only when `raw > 0`
  (zero incoming damage stays zero; the floor triggers on a real hit). TRUE
  damage bypasses everything.
- **Armor pierce** is the attacker's pipeline over the defender's final armor
  (`DamageInstance.armor_pierce`, stamped by `pierce_terms`): folded only when
  armor > 0, clamped at 0 (pierce never makes a hit bigger; breaking armor below
  0 is `sunder`'s job), floored to whole once, never merged into the defender's
  armor bins ([ADR 0065](../adr/0065-a-stat-may-be-a-pipeline-over-another-entitys-value.md)).
- **Both stats are read node-locally** via `NodeCombat.get_local_value`, which
  merges the node's `node_board` bins with the owner's board through one
  `ModifierBins.compute`, so a node-scoped `armor` modifier (a `bunker_addon`, a
  core-class aura) reaches the formula. They are live stats, never their board
  default (`.claude/rules/live-stats.md`). A formula that took a board instead
  of a node would discard every node-local defensive modifier while
  `combat_readout_card.gd` still displayed it: a stat that displays right and
  computes wrong.
- **The floor is a floor, not a cap:** negative `armor` pushes damage above raw,
  but only becomes visible once `raw - armor > min_damage_taken` (raw 1 / armor
  -1 / floor 3 still takes 3).
- **A negative net `min_damage_taken` makes a glancing hit heal the defender, on
  purpose.** `compute` returns the negative number as-is and
  `NodeCombat.take_damage` reclassifies the landing to `HitInstance.Kind.HEAL`
  before the HP pool moves. `bunker_addon.tscn` authors `-5`, affirmed by the owner 2026-09-04: "the whole
  design of sprinkling `-min_damage_taken` modifiers on the board is to allow to
  go <0 and actually heal from having sufficient armor / tanking low hits
  heals". Anything that clamps this at zero deletes a mechanic; anything that
  drops such a landing from a render pass is the bug fixed in
  `ArrowVolleyCoordinator`.

After mitigation, `take_damage` depletes the node's pool and fills the hit:
`effective_amount` is the post-mitigation number (on a flipped heal, the HP
actually restored), `hp_before` / `hp_after` / `hp_max` the bar's; on an
overkill the two disagree on purpose (`HitInstance.hp_before`, owner
2026-08-21). On a core node the crack (pool from > 0 to ≤ 0) moves every row
to the entity first ([ADR 0066](../adr/0066-a-cracked-core-hands-its-statuses-to-the-entity.md)), then the overflow reaches the
entity's `health` through `EntityCombat.take_pool_damage`. A depleted non-core
node marks its spill scale, then enters the cascade: live through
`notify_depleted` (→ `BattleSystem._on_node_depleted` → `apply_cascade`), on a
shadow through `EntityCombat.cascade_from`. The cascade's wound and chip
bypass mitigation ([stat-upkeep-and-combat.md](stat-upkeep-and-combat.md)
§ "Damage mitigation, DoT and healing"). A damage crit that is still `DAMAGE`
then spends crit-taken statuses (`NodeCombat.on_crit_taken`).

### Armor pierce, worked

`sunder` works **inside** the defender's armor bins (a −1 per stack, can go negative). `armor_pierce` works **on its output** (ADR 0065): the hit carries the attacker's pierce as `FoldTerms` (`DamageInstance.armor_pierce`, stamped by its producer via `Mitigation.pierce_terms` off the attacking node), and `Mitigation.effective_armor` folds it over the defender's *final* armor only when that is > 0, clamped at 0 and floored to whole; the `min_damage_taken` floor still applies last. Fixture: defender 4 / +50% / +2 = 8 → −3 ADD_BASE lands 5, −50% INC 4, ×0.5 4, SET 0 0. Producers opt out (`uses_board_pierce`) or add their own (`armor_pierce_modifiers`): `DamageEffect`, `PairedDamageEffect`, `AmmoType`, and the blade via `SwingContext`.

## CritRoll: the one crit implementation

changing: the head's crit is read before its riders and crit conditions leave compile, #1798; see docs/design/elements/hit-resolution.md

`CritRoll` (`attack/outcome/crit_roll.gd`) is the one crit rule shared by all
three attack modes; `crit_chance` / `crit_multiplier` are universal entity
stats, so a roll per mode would be three drifting implementations. A crit is
decided per hit (owner, 2026-08-21), at the landing itself (owner, 2026-10-07):

```
Land   CritRoll.decide(hit, rng, world)   draw + conditions -> is_crit,
                                          crit_multiplier, crit_tier
       CritRoll.apply(hit)                amount *= crit_multiplier
```

- `OutcomeApplier.land_one` draws right before the hit lands, in landing order,
  off `AttackOutcome.crit_stream`, reading the landing world (the shadow during
  resolve), so a status landed in an earlier beat of the same attack (a mark
  rider) reaches the chance of the hits behind it.
- **A hit crits first; its payload copies it.** A lead draws as it lands, and
  its riders land after it (ADR 0092; a rider asked first would decide its lead
  first, `CritRoll.decide`), so the one draw per lead precedes the whole payload
  and every rider `HitInstance.copy_crit_from` it: a status rider lands its
  stacks times `abs(crit_multiplier)`, a paired damage share its share times
  the multiplier. A mark rider lifts the hits of later beats, never its own.
- **A replay never draws:** a rebuilt `AttackRecord` carries no stream and lands
  the recorded crit. Every crit reader that runs before a landing (the VFX
  stamping `Projectile.crit_tier`, the floaters) reads a rebuilt record on the
  live replay, i.e. after the shadow resolve settled it.
- The multiply stays at the tail of `HitInstance.land_on`, after ranged's offense
  read and melee's spike-pop gate, so whatever number those settled is the number
  multiplied.

**A rider's crit is its hit's crit.** A hit crits once, as its own fact, before
any of its payload lands: `CritRoll.decide` draws the lead's `crit_chance` as
the lead lands, before any of its riders (they land after it), and every rider
copies it (`HitInstance.copy_crit_from`); a status rider lands the folded stacks
× `abs(crit_multiplier)`, so poison 1 + curse 1 on a ×2 crit land 2 + 2. A rider
never draws. A status-only hit (a spell whose landing is a bare status, `paired`
null) is a lead and rolls `crit_chance` on top of its stamped condition tier.
Consequence: curse, sunder and mark lift only the hits of later beats (an
aspect rider lands after every other hit of its own beat, ADR 0092), while a
hit that reads a mark still spends it with its crit.

`decide` in detail: a hit already `crit_decided` is a no-op; a rider decides
its lead, then copies it; a lead that does not `draws_own_crit()` (a
`CureInstance`) or has no positive amount (save a `StatusInstance`, amount 0
until it lands) draws nothing; otherwise one draw, and only when its folded
chance (`chance_for`: `crit_chance` read locally off the read node's slice,
plus the target's incoming overlays such as a mark) is above 0, so an
uninvested hit never shifts the stream. A tier above 0 is a crit at the
attacker's `crit_multiplier` (2.0 when the board has none). The stream is
`CritRoll.stream_for(resolve_seed)`, salted apart from magic's propagation
stream; seed 0 (a preview, an AI rollout) is a fixed stream.

## Statuses landing

changing: Greed neither doubles nor spends on terrain landings, #1798; see docs/design/elements/hit-resolution.md

A status hit is a `StatusInstance` an `ApplyStatusEffect` emitted.
`StatusInstance.land_on` duds it through `rider_gated` like any rider, and on
a node its own beat's hits stripped (the drain gates it, ADR 0092, shipped
as `FLAG_GATED`); picks the host (the entity iff the node is its owner's cracked core); folds the
attacker's `<id>_stacks_per_hit` over the authored power on the read node's
slice, adds `stack_terms`, multiplies by `abs(crit_multiplier)` and
`stack_scale`, rounds half-up to a whole count; zeroes it if the host blocks
the status; doubles it if the host's Greed arms; then `apply_status`. All of
that is decided once on the authority (`power_resolved`), and a rebuilt hit
lands the recorded power.

**Heat, Cold and Charge never make a row** (#1794): `apply_status` ends in
`NodeCombat.apply_status`, which asks `ElementRoster.for_status(def)`; an
element's own terrain def diverts into
`NodeCombat.add_terrain(element, round_half_up(power))` and never reaches
`StatusHost` (no row, camp, applier or `_may_host`; unallocated nodes take
it). Everything above the divert (the gate, the fold, crit and `stack_scale`) runs
as for any status; `*_resistance` does not filter it, and Greed's doubling and
spending on terrain is open (#1798). Every other def lands as a row, unchanged. The
bullet-by-bullet contract:
[status-effects.md](status-effects.md) § "StatusInstance.land_on: which slice,
which host"; the stacks fold and resistance: § "The DoT model".

## Go-off zero: Explosive detonation

changing: detonation is ported onto the gather as a disc `GoOff`, #1799; Burning's disc lands beside it, #1800; the Catalyst retag deletes it, #1801; the blade's explosive path goes, #1802; see docs/design/elements/go-offs.md

Today's only go-off is an Explosive detonation, and it is a hit like any
other. `DetonateEffect.arm(riders, load)` adds a detonation to a landing's
effects (a spell's `DetonateUse` load, an arrow or a blade's board blast at
load 0, unless a rider plants explosive); landing, it spends the charges the
node holds and, when its power is above 0, builds a `BlastEffect` whose hits
are appended to the same landing and placed after its hit, each stamped with
the blast's `blast_mark`, which `OutcomeApplier.apply` announces once. A blast replicates
the hit with explosive stripped, so a charged node it reaches goes off in turn,
once per node per `HitLanding.detonated` scope. A blade contact's two sides
are decided in `BladePopResolver.LiveGate`. The formula, reach, chains, the
blade contact and the knobs: [explosive.md](explosive.md); the calls:
[ADR 0061](../adr/0061-a-hits-explosive-load-resolves-through-the-intake-rows-face-and-a-blast-replicates-the-hit.md), [ADR 0062](../adr/0062-the-default-face-lives-on-the-status-def-and-a-blade-contact-lands-its-two-sides-on-two-target-sets.md).
