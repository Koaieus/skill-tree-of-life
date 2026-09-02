# Spell propagation — refactor toward filter / step / merger

Engineering-side architecture doc for the spell propagation pipeline. The
design-side (what spells *do* and why) lives in `docs/design/spells.md`;
this doc covers the code shape that has to support it.

Session-handoff format: where we are, where we're going, why, and the
migration queue.

---

## Where we are

`attack/spell/spell_resolver.gd` runs a single BFS queue: pop one
`CastSpell`, apply each `OnHitEffect` to it, then ask
`spell.propagation.next_hops(state)` for the children and append them.
Each `CastSpell` carries its **own** `visited: Array` and gets duplicated
on every fan-out in `SpellPropagation._propagate_to()`.

Existing `SpellPropagation` subclasses (`AllNeighboursPropagation`,
`HighestDegreePropagation`, `LowerDegreePropagation`,
`RankedStatPropagation`, `RandomWalkPropagation`, `NoPropagation`) all
share the same shape: filter neighbours, mint one `CastSpell` per pick.
The filter logic is duplicated across them (every subclass repeats the
`revisit_visited` / `only_enemy` checks).

Two consequences fall out of this design:

1. **No global visit ledger.** A diamond `A → {B,C} → D` hits D twice
   because each branch's `visited` only saw one shoulder. Worse, a Spark
   with `max_hops=3` over a moderately-connected graph procs ~28 hits
   because every fan-out forks the visited set. This is captured by
   `test/unit/spell/test_propagation.gd::test_diamond_double_hits_via_parallel_branches`
   with a TODO flagging the model as wrong.
2. **No merger.** When N branches converge on the same node in the same
   BFS wave, the resolver produces N independent hits — no way to express
   "add the incoming damage", "take the max", "cancel if overlapping".

This refactor fixes both, and in the process makes self-loops a
first-class mechanic (see Resonator in `spells.md`).

---

## Where we're going

Three small interfaces, plus a shared per-cast context, plus a
wave-based resolver. Each interface is intentionally **as scoped as
`RangeFinder`** — one virtual method, one job. RangeFinder's reusability
is the model.

### `PropagationFilter`

```gdscript
@tool
@abstract
class_name PropagationFilter
extends Resource

@abstract func allows(
    from_node: SkillNode,
    to_node: SkillNode,
    payload: CastSpell,
    ctx: PropagationContext) -> bool
```

Stock subclasses (slot into one or more `PropagationConfig`s):

- `OwnerFilter` — `enemy` / `ally` / `unallocated` / `any` (drops the
  duplicated `only_enemy` logic from every existing propagator)
- `MaxVisitsFilter` — reads `ctx.global_visit_count[to_node]` against
  `PropagationConfig.max_visits_per_node`; this is what subsumes both
  the old `revisit_visited` boolean and a future per-node hit cap
- `DegreeFilter` — strict-less / less-or-equal / strict-greater /
  greater-or-equal vs. current degree, measured inside each node's own
  territory (Leafblower ships less-or-equal). See `docs/domain/degree.md`
  for why entity degree and not graph degree.
- `NoSelfLoopFilter` — vetoes `to == from`. Self-loops are first-class here,
  so a spell that refuses them has to say so; leaving it to emerge from
  another rule is what shipped Cyclone with the opposite behaviour (#699).
- `CoreDistanceFilter` — closer-to-Core / farther-from-Core (Homing
  Decoring, Corifugal Bolt)
- `CompositeFilter` — AND/OR-combine children (matches `RangeFinder`'s
  composite pattern)
- `ExpressionFilter` — `Expression`-backed escape hatch for one-offs,
  modeled on `StatFormula`'s expression layer

### `PropagationStep`

```gdscript
@tool
@abstract
class_name PropagationStep
extends Resource

@abstract func step(
    current_node: SkillNode,
    payload: CastSpell,
    candidates: Array[SkillNode],
    ctx: PropagationContext) -> Array[CastSpell]
```

Receives the **already filtered** candidate list. Mints one `CastSpell`
per outgoing copy, applies any payload mutations (damage scaling,
hops--, custom).

Stock subclasses:

- `FanAllStep` — one copy per candidate, `damage *= damage_multiplier_per_hop`
  (covers Lightning / Crunch / Flood / Resonator)
- `TakeTopNStep` — sort by a ranker, take top N (collapses
  `HighestDegreePropagation` + `RankedStatPropagation` into one configurable
  shape: the ranker is composable too)
- `RandomPickStep` — `RandomWalkPropagation` equivalent, RNG-threaded
- `NoStep` — empty array (single-target spells)

### `IncidentReducer`

```gdscript
@tool
@abstract
class_name IncidentReducer
extends Resource

## Returns the resolved incident, or null to CANCEL (no effect lands,
## no further propagation from this node in this wave).
@abstract func reduce(
    incidents: Array[CastSpell],
    node: SkillNode,
    ctx: PropagationContext) -> CastSpell
```

Stock subclasses:

- `SumDamageReducer` — sum damages, MAX hops_left, union visited
- `MaxDamageReducer` / `MinDamageReducer` / `FirstReducer`
- `CancelIfMultiReducer` — null if `incidents.size() > 1`
- `CancelIfEvenReducer` — null if `incidents.size() % 2 == 0`
- `ExpressionReducer` — one-off escape hatch

`visited` union and `hops_left = max(...)` are baked-in defaults the
stock reducers all use — *not* author-facing knobs. The reducer's only
*real* responsibility is the damage decision; everything else has one
sane default.

### `PropagationContext`

Per-cast state, threaded through the whole resolution:

```gdscript
class_name PropagationContext
extends RefCounted

var global_visit_count: Dictionary  # SkillNode -> int
var graph: Graph
var caster: Entity
var seed_node: SkillNode
var rng: RandomNumberGenerator
```

Branches read & mutate it freely. The resolver bumps
`global_visit_count[node]` after each successful merger application.
`MaxVisitsFilter` reads it before allowing onward copies.

### `PropagationConfig`

The thing a `SpellDef` points at — composes the three interfaces plus
the scalar knobs that don't deserve their own class:

```gdscript
@export var filter: PropagationFilter
@export var step: PropagationStep
@export var reducer: IncidentReducer
@export var max_hops: int = 0
@export var max_visits_per_node: int = 1   # 1 = never-revisit; INT_MAX = uncapped
@export var hop_damage: HopDamageProgression = null   # null = damage carried verbatim
```

This replaces `SpellPropagation` entirely. `SpellDef.propagation` retypes
to `PropagationConfig`.

#### `max_hops` takes NO stat scaling — owner ruling, 2026-09-02

There are two different "spell hops" and they must never share a modifier:

| | what it means | where | scalable? |
|---|---|---|---|
| **Cast-range hops** | how far away a target may be | `HopRangeFinder.max_hops` | **yes** — this is what a reach stat tunes |
| **Propagation hops** | how many times the spell bounces in flight | `PropagationConfig.max_hops` | **no** |

> "bonus spell hops (cast 'range' gate) vs bonus spell hops (in flight spell
> lands more hops/bounces) — the former we are tuning right now, the latter one
> we should be very careful about, and possibly disable entirely until we find a
> proper way to tune it — adding max hops to a spell dramatically alters its
> performance" — owner, 2026-09-02

Runtime already honours this: `spell_resolver.gd` sets
`seed_state.hops_remaining = config.max_hops` **raw**. The only thing that ever
scaled it was the tooltip, which lied about the depth it printed — fixed
2026-09-02 (`b51c66f`).

**Why it cannot take a global modifier at all**, independent of tuning taste:
`max_hops` means two different things depending on whether the step
self-terminates. Trailblazer's 999 is a *backstop* — `trail_blazer_step.gd`
walks one path and stops at the first junction (degree > 2), so "+2 hops" does
nothing to it — while Cyclone's 8 is a *limiter*, and the same "+2" takes it
from 8 bounces to 10. One modifier, wildly different effect per spell. Any
future propagation tuning has to be **per-step-strategy, not a board stat**.

Bounce count is superlinear in effect, unlike reach. Keep this in view when
adding any reach stat: it feeds `HopRangeFinder` only.

### Damage: one coefficient × one board stat (D-32, #274)

The scalar damage knobs above are gone. There is exactly one absolute number
per spell and one per caster:

```
seed  = spell_damage(state.source) × SpellDef.power
hop n = f(hop n-1)     f = the spell's HopDamageProgression
```

- `spell_damage` is an ordinary board stat (base 1, +1 per 10 INT — the same
  shape as `blade_damage`/STR and `ranged_damage`/DEX), so node-local addons
  ("mana font") stack on it per-node.
- It is read from **`state.source`** — the node cast FROM — via
  `SkillNode.get_local_value`, which merges the node board with its **owner's**
  board. Reading `state.current_node` would let the defender buff the spell
  landing on them.
- It is evaluated **once, at the seed**, and stamped on `CastSpell.seed_damage`
  (copied verbatim by `_propagate_to`, like `seed_node`). Re-reading per hop
  would compound INT — INT² by hop 2. The formula itself lives in
  `SpellResolver.impact_damage()` — the number the primary target takes;
  `CastSpell.seed_damage` is the same float carried forward for hop
  progressions to fraction themselves against (#396).
- `PropagationConfig.seed_damage_fraction` was deleted (`1.0` in every spell;
  its "¼ power then ramp" case is a lower `power`).

`HopDamageProgression` (the old `HopDamage`, renamed to kill the
`…Damage`/`Propagation` collision) owns the *shape*, and **each class declares
whether the spell scales with the caster**:

| Class | Behaviour | Math | Scales with caster |
|---|---|---|---|
| `MultiplyProgression` | `damage × factor` | geometric | yes |
| `ScaledAddProgression` | `damage + seed × seed_fraction_per_hop` | arithmetic, relative | yes |
| `FlatAddProgression` | `damage + increment` | arithmetic, absolute | **no — deliberately** |
| `ExpressionProgression` | authored expression | escape hatch | author's choice |

`FlatAddProgression`'s absolute increment is a *compressive* curve (7× its own
seed at INT 10, 1.12× at INT 1000) — a wanted spell personality, not a
dimensional bug. What D-32 forbids is an *undeclared* absolute. See the D-32
amendment in `docs/design/mvp_decisions.md`, and the guard test in
`test/unit/spell/test_spell_damage_scaling.gd`.

**`ExpressionProgression`'s seed identifier is `seed_damage`, not `seed`** —
Godot's `Expression` parser reads a bare `seed` as the built-in PRNG function
and fails to parse with "Expected '('". Same collision that named
`CastSpell.seed_node`.

---

## Resolver flow (wave-based)

Today's resolver pops one state at a time. The new resolver processes
**waves** (BFS frontiers) so the merger can reduce simultaneous arrivals
before effects fire.

```
seed_wave = [initial CastSpell at seed_node]
while wave not empty:
    # 1. group by target node
    incidents_by_node = group(wave, key=current_node)

    # 2. merge per node
    merged = []
    for node, incidents in incidents_by_node:
        resolved = config.reducer.reduce(incidents, node, ctx)
        if resolved == null:    # CANCEL — no effect, no propagation from here
            continue
        merged.append(resolved)

    # 3. apply effects to merged incidents, bump ctx.global_visit_count
    for state in merged:
        for eff in spell.on_hit_effects:
            eff.apply(state, outcome)
        ctx.global_visit_count[state.current_node] += 1

    # 4. compute next wave: filter candidates, then step
    next_wave = []
    for state in merged:
        if state.hops_remaining <= 0: continue
        candidates = [nb for nb in graph.get_neighbours(state.current_node)
                      if config.filter.allows(state.current_node, nb, state, ctx)]
        next_wave.append_array(config.step.step(state.current_node, state, candidates, ctx))
    wave = next_wave
```

Notes:

- `current_node` keying assumes node-target spells; when edge/area
  targeting lands later, the grouping key becomes
  `(target_kind, target_ref)` and the merger gets a polymorphic
  payload — out of scope today.
- The resolver remains side-effect free w.r.t. world state (damage
  application still deferred to the VFX layer; merged `CastSpell`s
  carry their `.damage` for the coordinator to apply).
- BFS hop-monotonic ordering is preserved — the VFX layer's stagger
  still works without changes.

---

## Why this shape

- **Filter / Step / Merger are orthogonal axes.** Mixing-and-matching
  three small subclasses + a handful of scalars gives a combinatorial
  space of spell behaviours. The design-side `spells.md` already
  enumerates a dozen distinct spells expressible this way.
- **Each interface stays RangeFinder-small.** One virtual method, no
  state, easy to read and test in isolation. Composable.
- **Self-loops become a mechanic, not a bug.** A self-loop node
  propagating to itself produces 2 incidents in the next wave; SUM
  reducer collapses them into a doubled hit. That's Resonator's whole
  identity. The current model literally cannot express it.
- **Diamond double-hits stop being implicit.** They happen iff the
  spell's reducer is SUM and visit cap allows it. The existing
  `test_diamond_double_hits_via_parallel_branches` becomes a `SumDamageReducer`
  test instead of a captured quirk.
- **Configuration replaces subclassing for 95% of spells.** Authors
  ship a new `.tres`, not a new script. The Expression escape hatches
  cover the final 5% without going to a custom subclass.

### Alternatives ruled out

- **Per-branch shared visited via reference-counting** — keeps the
  current per-branch payload model but mutates a shared set. Same
  semantics as `PropagationContext.global_visit_count` but uglier and
  harder to test. Rejected for plain shared context.
- **`ONCE_PER_BRANCH` visit policy** as an authored option — produces
  asymmetric, incoherent damage distributions (tic-tac-toe center hit
  1x, corners 2x, edges 4x). Nobody would design a spell *intending*
  this. The current behaviour is implementation artifact, not feature.
  Rejected.
- **Cross-wave merger (buffer all arrivals across the whole cast)** —
  would let a late-arriving incident via a long cycle merge with an
  earlier one. Breaks the per-tick feel, requires buffering the full
  resolution, and unclear UX. Merger is wave-local; late arrivals are
  just additional independent hits gated by `max_visits_per_node`.
- **Putting damage scaling on the Step subclass exclusively** — would
  force every spell to use a Step variant just to change falloff.
  Keeping `damage_multiplier_per_hop` as a scalar on `PropagationConfig`
  + letting `FanAllStep` read it covers 90% of cases without subclass
  proliferation. Custom Step subclasses can still override.

---

## Migration plan

The codebase has 2 spell `.tres` files (`spark.tres`, `lightning.tres`)
and a dev-only spell playground — migration is cheap.

1. Write the new types (`PropagationConfig`, `PropagationContext`,
   `PropagationFilter` + stock subclasses, `PropagationStep` + stock
   subclasses, `IncidentReducer` + stock subclasses).
2. Rewrite `SpellResolver.resolve()` to wave-based. Keep its signature.
3. Update `SpellDef.propagation` to type `PropagationConfig`.
4. Port `spark.tres` and `lightning.tres` to the new config shape.
5. Update `test/unit/spell/test_propagation.gd`:
   - Remove the TODO.
   - `test_diamond_double_hits_via_parallel_branches` → becomes a
     `SumDamageReducer` assertion (sum of damages on D, not 2 separate
     hits), and a sibling test asserting `MaxDamageReducer` produces 1 hit.
6. Add tests covering: filter dispatch, max_visits_per_node enforcement,
   reducer CANCEL kills onward propagation, cross-wave revisit when
   max_visits > 1.
7. Author 2–3 new spell `.tres` from `spells.md` (Leafblower, Bruiser,
   Resonator are the obvious early shippers — Resonator needs self-loop
   procgen + edge rendering before it's playable, but the spell itself
   is just a `.tres`).
8. **Delete** the old `SpellPropagation` hierarchy. No need to keep both
   alive — there's no third-party content to break.

Refresh the class cache (`godot --headless --editor --quit`) after step 1
and after step 8; `git diff` the editor-touched scenes/.tres as per
`.claude/rules/godot-workflow.md`.

---

## The outcome → VFX seam: the `PropagationEvent` timeline (#46)

The resolver's job ends at a **pure `AttackOutcome`** — no world state touched
(damage is applied later, by the VFX layer, on projectile arrival). That purity
is load-bearing: it's why `resolve()` doubles as a preview for AI scoring and
tooltips. The question #46 answers is *what shape* that outcome hands to VFX.

### Two projections over one resolution

- **`hits: Array[HitInstance]`** — the **primary, universal** flat list.
  *Every* attack type appends to it: spell `DamageEffect`/`HealEffect`,
  `RangedAttackPlan`, `MeleeAttackPlan`. It is **not** derived from anything;
  it is producer-populated. `DamageInstance` and `HealInstance` both extend
  `HitInstance` (#381 unified the old parallel `hits`/`heals` lists) — a
  `HitInstance.kind` field (`DAMAGE`/`HEAL`) tells a consumer which.
- **`timeline: Array[PropagationEvent]`** — **additive, spell-only** structure.
  The `SpellResolver` builds it; melee/ranged leave it empty. Each event
  *references* the same `HitInstance` object(s) already in `hits` (shared, not
  copied) via `event.hits`, which is empty (not null — #381 made this a list)
  for a zero-damage / utility landing that still gets a probe event so it
  animates.
- **`cancellations: Array[SpellCancellation]`** — kept as a replay projection
  *alongside* the new `Verb.CANCEL` events. Additive, not replaced.

The old path had `MagicBounceCoordinator._group_by_hop()` **re-derive** wave
structure by grouping `hits` on `hop_index` — throwing away the predecessor
chain and never reading `cancellations`. The timeline promotes what the resolver
already knew at emission time. `hits` stays as the compatibility surface so the
~15 existing readers (battle_system, both coordinators, tests) don't churn.

### `PropagationEvent`

```gdscript
class_name PropagationEvent extends RefCounted
enum Verb { JUMP, EDGE, SELF_LOOP, CANCEL }   # a, b, e, d
var beat: int                        # = CastSpell.hop_index (== wave_index; the two stay lockstep)
var verb: Verb
var origin: SkillNode                # probe travels FROM here (predecessor ?? source)
var target: SkillNode                # lands here (current_node)
var predecessor: SkillNode = null    # NODE ref this pass — event→event fork-tree link deferred
var predecessors: Array[SkillNode] = []       # every arc that converged here, in incident order (#542)
var visit_index: int = 0                      # the nth time this cast has landed on `target`, 0-based (#543 D6)
var is_terminal: bool = false                 # the walk ENDED here by terminal rule, not merely last-appended
var incident_shares: PackedFloat32Array = []  # per-arc damage share, ALIGNED with `predecessors` (#707)
var turn_sign: float = 0.0                    # +1 / -1 / 0 — which way the storm turned (#707)
var closed_ring: Array[SkillNode] = []        # the simple cycle this landing CLOSED, in walk order (#710)
var hits: Array[HitInstance] = []    # shared refs into `hits`; empty for CANCEL / zero-damage
# crit_tier lives on each HitInstance now (#381); event.max_crit_tier() derives
# the per-event emphasis value across `hits`.
```

> The five fields above `hits` were added after #46 and this block used to omit
> them. `predecessors`, `visit_index` and `is_terminal` arrived with #542/#543;
> `incident_shares` and `turn_sign` with #707; `closed_ring` with #710. Each was added for exactly one
> spell that could not otherwise be drawn — which is the pattern, not an
> exception: the seam widens when the picture provably cannot re-derive
> something, and never merely because it would be convenient.

### `incident_shares` — why rank had to cross the seam (#707)

Cyclone splits its damage across turn-ranks, and rank is the whole mechanic: the
sharp turn circulates, the wide turns radiate. The VFX layer cannot recover it.
`CycloneStep` holds the coefficient as a **local**, multiplies `damage` by it and
drops it; `CycloneReducer` then **sums** every incident, and the crit multiplies
again at landing. A landed amount is not invertible.

Three things make the shape what it is:

- **A float share, not the rank ordinal.** The share has `closing_gain` folded
  in, so a closing rank-1 arc reads as genuinely heavier than an ordinary one —
  which it is. An ordinal would flatten exactly that, and a float is directly
  usable as a brightness or width scalar with no lookup.
- **Aligned with `predecessors`, not one scalar per landing.** The coordinator
  already draws one bolt per `predecessors` entry, and a convergence is precisely
  a strong arc meeting a weak one. That *is* the reinforcement mechanic, and the
  only moment a player can see it. `SpellResolver` gathers both arrays in the
  same loop off the same `incidents`, so they are aligned by construction rather
  than by a downstream assertion.
- **The seed reports 1.0**, meaning "undivided" — louder than any coefficient,
  because it was not minted by a turn at all. Every non-splitting spell reports
  1.0 throughout, so a reader may treat the share as a weight unconditionally.

`turn_sign` rides along because handedness is not derivable either. Measuring a
turn needs the direction the front arrived *into* its origin, which lives in a
**different event** — and `predecessor` is a node ref with the event→event link
deferred, while uncapped revisits (b98a2ca) mean a node is the target of many
events. "Which one fed this arc" is genuinely ambiguous downstream. It is
constant for a whole cast (`Curl.rank` turns one fixed way at every node), so
`IncidentReducer._merge_payload_defaults` carries it first-wins through a merge —
exact, not a choice. `arrival_share` is deliberately **not** merged: it describes
one arc's mint, and once the fronts have summed the merged payload has no share.

### `closed_ring` — the ring, because a ring cannot be re-derived (#710)

Cyclone's closing hop is the payoff of the whole #703 redesign (the crit, plus
`closing_gain` feeding forward as sustain) and it used to light at most **one
node**. Lighting the ring *as* a ring needs the ring, and it lives in
`CastSpell.visited` — a resolver-local the event never carried.

- **The resolver stamps it where the crit is stamped.** `CycloneStep.closed_ring()`
  truncates `visited` to *exactly* the loop on every close (that truncation is
  what makes every `CycleCritCondition` crit a real simple cycle of length ≥ 3),
  and `CycloneReducer` hands a closer's lineage through whole. So the stamp is one
  line — `ev.closed_ring = state.visited.duplicate()` when `state.closed_cycle` —
  and `closed_ring` is non-empty on exactly the landings that closed something.
- **Array order IS the storm's rotation.** The ring comes back in walking order
  ending at the landed node, so consecutive pairs are its edges and
  `ring[-1] → ring[0]` is the edge the closer just crossed — the Nth edge, not a
  seam. The VFX layer derives edges from those pairs; nothing promotes `Edge`
  objects or stable ids, and no `turn_sign` read is needed to lap it.
- **Node refs, like `predecessors` and `target`.** An event is local replay
  output and never a command, so the sync rule's "no node refs" does not apply.

The picture is `ui/vfx/projectile/visual/cyclone_ring_flash.tscn`, spawned once
per closing event through `MagicBounceCoordinator.ring_visual` — once per
*event*, not per arc, because a merged landing draws one bolt per predecessor
and an additive polyline drawn three times reads as a brightness bug.

**Verb is resolver-stamped, not geometry-inferred** — it *cannot* be recovered
from positions (a self-loop's origin == target). The resolver knows it at
emission:

| condition (at the landed `CastSpell`)     | verb        |
|-------------------------------------------|-------------|
| `predecessor == null` (the seed)          | `JUMP` (a)  |
| `target == predecessor` (self-loop edge)  | `SELF_LOOP` (e) |
| otherwise (stepped across an edge)        | `EDGE` (b)  |
| reducer returned `null` (fizzle)          | `CANCEL` (d)|

There is deliberately **no `HIT` verb**. "Hit the node" (c) is the *arrival
phase* every non-`CANCEL` event performs — it maps to the visual contract's
existing `_on_arrival()`, not to a distinct event kind. Reserve a `HIT` verb only
if a genuine no-travel case (aura / in-place application) ever needs it.

`SELF_LOOP` is defined but **untestable until self-loops are procgen-seeded and
rendered** (see Open Question #4 below and `spells.md` OQ#10). Don't claim it
verified this pass.

### What the coordinator does with it

`MagicBounceCoordinator` walks the timeline grouped by `beat` instead of
`_group_by_hop`. Its `is_empty()` guard flips from `hits` to `timeline` — a net
improvement: a **pure-utility spell (`power` 0) now renders its path**
instead of no-op'ing on an empty `hits`. The fixed wave clock is untouched:
`wave_started(beat, count)` still fires per beat regardless of lingering visuals
(the load-bearing contract in `.claude/rules/spell-vfx.md`).

The **movement verb → `ProjectilePath`** mapping and the impact-pinned
three-clocks lifetime (windup / linger past 1) are **follow-on work**, not this
cut. This issue lands the *shape*; the VFX-timing rework builds on it.

---

---

## Per-branch payload state and the merge trap (#696)

`CastSpell` carries per-branch state beyond damage — `visited`, and since
Cyclone also `came_from` / `closed_cycle`. **The stock merge silently decides
what happens to all of it, and its defaults are wrong for anything that reads
that state as a rule rather than as trivia.**

`IncidentReducer._merge_payload_defaults` does two things worth knowing before
you author the next payload field:

- **`visited` is UNIONED.** Fine when the trail is only a revisit guard. Wrong
  the moment the trail *means* something: Cyclone crits on landing in its own
  trail, so a union crits on ground the surviving lineage never walked — and
  only when it happened to converge with someone who did. Inconsistency wearing
  flavour's clothes. `CycloneReducer` keeps **the winning incident's trail**
  instead.
- **`predecessor` keeps only `incidents[0]`'s.** It is the canonical "the
  projectile flew from somewhere" reader for VFX, and it was never meant to be a
  *set*. A rule that needs every direction the fronts arrived from must carry its
  own array field — that is what `CastSpell.came_from` is, and the full set does
  also exist on `PropagationEvent.predecessors` (#542), but only for the event,
  after the fact.

Three questions a new payload field has to answer, and the reducer is the only
place that can:

1. **How does it merge?** Union, winner-takes, max, OR — pick deliberately.
2. **Does any incident's state DOMINATE?** Cyclone's does: if one front closed a
   cycle, the merged payload resets outright (empty veto, trail restarted)
   rather than unioning in a non-closer's veto. Without that, an unrelated front
   silently weakens someone else's reset — a reset that sometimes isn't one.
3. **Where is it stamped?** At **mint, in the step**, if the answer depends on
   the parent's state. By landing time `_propagate_to` has already mutated the
   child's copy and a reset may have cleared it, so the fact is unrecoverable.
   The crit condition then just *reads* the stamped flag — the Design A split
   `ConvergenceCritCondition` documents, and the reason `CycleCritCondition` is
   a one-line predicate rather than a re-derivation.

The payoff for getting (1) right is not just correctness — but Cyclone is also
the cautionary tale. Its veto-union made the spell a **parity detector**
(counter-rotating fronts extinguished on even rings and lapped home on odd
ones), nothing in it was authored to do that, and at #703 the parity was
**removed as unwanted**: it was never a designed property, only the residue of a
rotation-blind fan. Merge semantics are where emergent behaviour lives, which
cuts both ways — emergent is not the same as intended, and a merge rule can
manufacture a whole mechanic nobody asked for. Cyclone now sums (see
`CycloneReducer`) and gets its identity from a curl instead.

---

## Open questions / queue

1. ~~Should `seed_damage_fraction` move into the Step?~~ **Closed** — the knob
   was deleted outright in #274 (D-32): `1.0` in all seven spells, and its
   motivating case is expressible as a lower `SpellDef.power`.
2. **Multi-seed targeting.** When RangeFinder eventually returns N
   seeds (AoE / chain-of-N spells), do they share a merger pool (one
   BFS with N starts, merger fires on overlaps) or run as N independent
   casts? Leaning shared, but the call can wait until a multi-seed
   spell actually wants implementing.
3. **CANCEL telemetry.** A `CancelIfMultiReducer` firing is a *real
   game event* — the spell visibly fizzles where it overlaps itself.
   Probably wants a VFX hook (one-time "pop" at the cancelled node) and
   maybe an entry in `AttackOutcome`. Out of scope for the first cut.
4. **Self-loop rendering & procgen seeding.** Not propagation code, but
   the propagation refactor surfaces it: without rendered self-loops
   the player can't see Resonator setups. Tracked in `spells.md` Open
   Question #10.
