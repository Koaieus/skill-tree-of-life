# Spell propagation — filter / spread / mint / merger

Engineering-side architecture doc for the spell propagation pipeline. The
design side is `docs/design/spells.md`; this doc covers the code shape that
supports it. Infusion (a per-cast fifth component) is
[ADR 0047](../adr/0047-infusion-is-a-per-cast-fifth-spell-component.md).

**The pipeline in one line:**
per landing, on **departure** the filter *narrows* → the spread *selects* → the
config *mints*; on **arrival** the reducer *merges* → the effects
*transform / emit* → the conditions *elevate*. Every stage has exactly one
role and no class does another's job — a spell's tooltip is generated from
the stages because of that.

`attack/spell/spell_resolver.gd` runs a wave-based BFS over `CastSpell`s with a
**global visit ledger** (`PropagationContext.visit_count`) and a per-landing
**reducer** that merges converging branches. The stock classes live under
`attack/spell/propagation/{filter,spread,reducer,ranker,progression}/`;
`max_visits_per_node` is enforced inline by the resolver, not by a filter. The
spells are the `.tres` files in `attack/spell/defs/`.

**Every stage but the reducer takes a `LandingContext`, not a decomposed arg
list.** Lifetime decides the home: per-cast facts (`outcome`, the
world, the crit RNG) live on `PropagationContext`; per-landing facts (the
landed node, the resolved payload, the incidents that fed it) live on
`LandingContext`, built once per landing right after the reducer returns and
reused for that landing's whole life — arrival (effects, crit conditions) and
departure (filter, spread) alike. `IncidentReducer` is the one exception: it
*makes* the landing, so none exists yet when it runs, and it takes
`PropagationContext` directly. See "`LandingContext`" below.

---


## Pipeline stages

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

## Pairwise — the 95% case. A set-level filter DERIVES this from `narrow`.
## `from_node` is `lctx.node`; `payload` is `lctx.payload`.
@abstract func allows(to_node: SkillNode, lctx: LandingContext) -> bool

## Set-level. Defaults to the `allows` loop; override only when the rule
## genuinely needs the whole candidate set at once.
func narrow(candidates: Array[SkillNode], lctx: LandingContext) -> Array[SkillNode]
```

**Set-level narrowing lives here and nowhere else.** A spread is purely
"sort by ranker, take N" — it never narrows.

Stock subclasses (slot into one or more `PropagationConfig`s):

- `OwnerFilter` — `enemy` / `ally` / `unallocated` / `any` (drops the
  duplicated `only_enemy` logic from every existing propagator)
- Max visits — not a filter: the resolver reads `ctx.visit_count(to_node)`
  against `PropagationConfig.max_visits_per_node`
- `RankThresholdFilter` — a `NodeRanker` score compared against the CURRENT
  node's: strict-less / less-or-equal / strict-greater / greater-or-equal.
  With `DegreeRanker` that is degree measured inside each node's own
  territory, which is what Leafblower (less-or-equal) and Reverberator
  (greater-or-equal) ship; see `docs/domain/degree.md` for why entity degree
  and not graph degree. With any other ranker it is the same rule on another
  metric — one implementation of "candidate vs current", not two.
- `TopTiesFilter` — set-level: keeps the candidates tying for highest (or
  lowest) `NodeRanker` score. Overrides `narrow`.
- `NoSelfLoopFilter` — vetoes `to == from`. Self-loops are first-class here,
  so a spell that refuses them has to say so; no other rule covers them
  (`BacktrackFilter` does not).
- `BacktrackFilter` — vetoes travel back into any node in the payload's
  `came_from` set (the set, not `predecessor`, so a merged payload refuses every
  direction its fronts arrived from). An empty set allows everything, so a
  cycle-closing child minted with an empty `came_from` needs no branch.
  `attack/spell/propagation/filter/backtrack_filter.gd`.
- `CoreDistanceFilter` — closer-to-Core / farther-from-Core (Homing
  Decoring, Corifugal Bolt)
- `CompositeFilter` — AND/OR-combine children (matches `RangeFinder`'s
  composite pattern). `narrow` in AND mode narrows SEQUENTIALLY, each child
  over the previous one's survivors — the AND of pairwise children, and the
  thing that gives a set-level child its meaning ("tied for highest *among
  what the earlier filters left*"), so order matters once one is present.
  OR mode is the union of each child's narrowing of the full set.
- `ExpressionFilter` — `Expression`-backed escape hatch for one-offs,
  modeled on `StatFormula`'s expression layer

### `PropagationSpread`

```gdscript
@tool
@abstract
class_name PropagationSpread
extends Resource

## `current` is `lctx.node`; `payload` is `lctx.payload`.
@abstract func select(eligible: Array[SkillNode], lctx: LandingContext) -> Array[PropagationPick]
```

Receives the **already narrowed** candidate list and answers one question:
*where does this landing's expansion go, and with what share?* It returns
`PropagationPick`s and **nothing else** — a spread never constructs a
`CastSpell`, never does damage math, never writes `hops_remaining`. The
payload is read-only inside `select`.

`PropagationPick` (`propagation/propagation_pick.gd`, RefCounted) is a
destination plus the facts the spread decided about it, every one typed:
`node`, `share` (the child's `arrival_share` IS this number), and the curl's
stamps — `arrival_bearing`, `turn_sign`, `closed_cycle`, `came_from`,
`lineage_override` (non-empty = the ring a closing hop walked, replacing the
child's `visited`). No dictionary: every writer of a field is one grep away.

Stock subclasses (`propagation/spread/`):

- `FanAllSpread` — one full-share pick per eligible node
  (covers Lightning / Crunch / Flood / Resonator)
- The Trailblazer walk lives in its filter + slam, not a spread: the `ExpressionFilter` clause `from_entity_degree <= 2 and to_entity_degree >= 2` (`trail_blazer.tres`) and the `ScaleDamageEffect` + `JunctionCondition` pair. Design prose: `docs/design/spells.md` § Trailblazer.
- `TakeTopNSpread` — sort by a ranker, take top N. Sorting and picking ONLY —
  narrowing the set first is `RankThresholdFilter` / `TopTiesFilter` on the
  filter side. `NodeRanker` and its subclasses live in `propagation/ranker/`,
  not under `spread/`, because filter and spread both consume them.
- `RandomPickSpread` — random pick, RNG-threaded
- `NoSpread` — empty array (single-target spells)
- `CycloneSpread` — ranks the eligible nodes by turn (`Curl.rank`) and picks
  one per authored rank; the rank coefficient (× `closing_gain` on a closing
  hop) is the pick's `share`. **The damage split happens in `mint`, nowhere
  else** — the spread only decides the number.

**A spread never transforms damage on arrival, and never decides that the
walk is over.** Both are authored elsewhere:

- the **slam** — a `ScaleDamageEffect` gated on a `JunctionCondition`, authored
  before `DamageEffect` in `SpellDef.on_hit_effects`;
- the **stop** — a `from_entity_degree <= 2` clause on the spell's
  `ExpressionFilter`. The walk ends at a junction because nothing is eligible
  to leave one.

### `LandingCondition`

```gdscript
@tool
@abstract
class_name LandingCondition
extends Resource

## `state` is `lctx.payload`; `target` is `lctx.node`; `outcome` is
## `lctx.cast.outcome`.
@abstract func evaluate(lctx: LandingContext) -> bool
```

A pure, read-only predicate over ONE landing, named for the question rather
than an answer. Two consumers:

- **crits** — `SpellDef.crit_conditions`, OR-ed per landing by
  `SpellResolver._stamp_crit_conditions`. The *slot* is the crit consumer, the
  predicate is not.
- **conditional on-hit effects** — `ScaleDamageEffect.when`.

Stock subclasses: `LeafCondition`, `SelfLoopCondition`, `CycleCondition`,
`ConvergenceCondition`, `JunctionCondition` (entity degree > 2), in
`attack/spell/condition/`.

### `ScaleDamageEffect`

An `OnHitEffect` that scales `CastSpell.damage` in place — `MULTIPLY` /
`SQUARE` / `MULTIPLY_BY_DEGREE`, optionally gated by a `LandingCondition`
(null = always) — and emits nothing itself. Author it **before** `DamageEffect`
and the damage effect emits the scaled number; effects already run in order
over the one mutable `CastSpell`, so this is that contract used, not a new one.

Two consequences worth stating rather than rediscovering:

- **Effects run before departure**, so a scaled arrival is what the next hop
  inherits. A mid-walk scale therefore compounds; a one-shot spike wants a
  condition that also ends the walk.
- **It scales the MERGED arrival**, after the `IncidentReducer`. Under
  `MULTIPLY` that agrees with scaling each branch before the merge
  (distributivity; max / first-wins outright); under `SQUARE` with a summing
  reducer it differs, and scaling the merged arrival is the intended reading.

### `IncidentReducer`

```gdscript
@tool
@abstract
class_name IncidentReducer
extends Resource

## Returns the resolved incident, or null to CANCEL (no effect lands,
## no further propagation from this node in this wave). Takes the CAST
## ledger, not a LandingContext — the reducer MAKES the landing, so
## none exists yet when it runs.
@abstract func reduce(incidents: Array[CastSpell], cast: PropagationContext) -> CastSpell
```

Stock subclasses:

- `SumDamageReducer` — sum damages, MAX hops_left, union visited
- `MaxDamageReducer` / `FirstReducer`
- `CancelIfMultiReducer` — null if `incidents.size() > 1`
- `CycloneReducer` — Cyclone's converging fronts add their power
- `ExpressionReducer` — one-off escape hatch

`visited` union and `hops_left = max(...)` are baked-in defaults the
stock reducers all use — *not* author-facing knobs. The reducer's only
*real* responsibility is the damage decision; everything else has one
sane default.

#### The stack fold (#1489)

Status riders are spell-wide, so every arrival carries the same status set;
what differs per arrival is its **stack weight**, `CastSpell.stack_weight`
(seeded 1.0, copied by `mint`, shaped per hop by `PropagationConfig.hop_stacks`
— a `HopDamageProgression` applied as `apply(weight, 1.0, hop_index)`, null =
unchanged). The reducer's `stack_fold` (MAX / SUM / MIN / FIRST, default MAX —
attacker-favoured, the owner's call) folds the incidents' weights via
`fold_stacks(incidents)` into the landing's starting `LandingContext.stack_scale`;
no reducer folds MAX. `ScaleStacksEffect` and the crit multiply onto it, and
`StatusInstance.land_on` rounds the row once, half-up, after crit × scale
(stacks are integer rows, ADR 0032).

- **The fold is per-landing, never carried.** The merged payload carries the
  MAX of its incidents' weights, so a SUM spell lands one share per converging
  branch — bounded by degree × visits, never by path count (a double diamond
  lands 2× at each convergence, not 4× at the second).
- **Across beats and casts** the status row's own `reapply` still governs.
- **Author-facing text:** `fold_description()` names a non-default fold
  ("Stacks add where branches meet."); `PropagationConfig.get_description`
  appends it, since every stock reducer overrides `get_description`.
- Parked: per-arrival *different* statuses (no author yet); stack
  progressions beyond the stock progression classes.

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
var outcome: AttackOutcome    # one per resolve_against (#356) — a cast fact
```

Branches read & mutate it freely. The resolver bumps
`global_visit_count[node]` after each successful merger application and reads it
(against `max_visits_per_node`) before allowing onward copies. `outcome` is set
once, up front in `resolve_against`, and is what `LandingCondition.evaluate` reads.

### `LandingContext`

Per-landing state, built by the resolver once per node a wave resolves onto —
right after `IncidentReducer.reduce` returns — and reused for that landing's
whole lifetime: arrival (`OnHitEffect`s, crit `LandingCondition`s) *and*
departure (`PropagationFilter`, `PropagationSpread`).

```gdscript
class_name LandingContext
extends HitLanding   # inherits attacker, source, origin, target, structural_key, paired, hits (ADR 0049)

var cast: PropagationContext   # the per-cast ledger this landing belongs to
var node: SkillNode            # the landed node — `from` on departure, `target` on arrival
var payload: CastSpell         # the reducer's resolved state — mutable; effects mutate it IN ORDER
var incidents: Array[CastSpell]  # what arrived here this wave, before the merge — provenance only

func ownership_bit_of(n: SkillNode) -> int
func is_allocated_in_world(n: SkillNode) -> bool
func local_value_of(n: SkillNode, stat_id: StringName) -> Variant
func visit_count(n: SkillNode) -> int
func fill_landing() -> void    # sets the inherited HitLanding fields from cast + payload; hits = cast.outcome.hits by reference
```

**Fields are fixed at construction, but `payload` is not immutable through
them.** It is the one mutable `CastSpell` that on-hit effects mutate in
order — `ScaleDamageEffect` running before `DamageEffect` relies on exactly
that. The four forwarding accessors exist so a
stage never reaches through `.cast` for the questions the world contract
answers — `ExpressionFilter` and `StatRanker` go through `lctx.*`, never
`lctx.cast.*`.

`LandingContext.for_test(payload, node, cast, incidents)` is the fixture
convenience every isolated stage test uses — all four params optional, `cast`
defaults to a fresh `PropagationContext` (with a fresh `AttackOutcome` filled
in if none is set), so a hand-built condition/effect test never dereferences
a null.

### `PropagationConfig`

The thing a `SpellDef` points at — composes the three interfaces plus
the scalar knobs that don't deserve their own class:

```gdscript
@export var filter: PropagationFilter
@export var spread: PropagationSpread
@export var reducer: IncidentReducer
@export var max_hops: int = 0
@export var max_visits_per_node: int = 1   # 1 = never-revisit; INT_MAX = uncapped
@export var hop_damage: HopDamageProgression = null   # null = damage carried verbatim

func mint(payload: CastSpell, pick: PropagationPick) -> CastSpell
```

**`mint` is the one place a child `CastSpell` is built** (*owner: "Step returns
picks; config mints."*): `damage = (hop_damage.apply(parent, seed,
hop_index) if hop_damage else parent) × pick.share`; `hops_remaining - 1`;
`hop_index + 1`; `visited` = parent trail + destination (or the pick's
`lineage_override`); caster / graph / rng threaded; then the pick's stamps
copied verbatim (`arrival_share = share`, `arrival_bearing`, `turn_sign`,
`closed_cycle`, `came_from`). The resolver calls `select` once per landing and
`mint` once per pick. Progression first, share second, so an authored ramp
composes with a spread's split.

`SpellDef.propagation` is a `PropagationConfig`.

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

Runtime honours this: `spell_resolver.gd` sets
`seed_state.hops_remaining = config.max_hops` **raw**, and the tooltip prints the
same raw depth.

**Why it cannot take a global modifier at all**, independent of tuning taste:
`max_hops` means two different things depending on whether the walk
self-terminates. Trailblazer's 999 is a *backstop* — it walks one path and its
filter stops it at the first junction (entity degree > 2), so "+2 hops" does
nothing to it — while Cyclone's 8 is a *limiter*, and the same "+2" takes it
from 8 bounces to 10. One modifier, wildly different effect per spell. Any
future propagation tuning has to be **per-spread-strategy, not a board stat**.

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
  (a "spell font") stack on it per-node.
- It is read from **`state.source`** — the node cast FROM — via
  `SkillNode.get_local_value`, which merges the node board with its **owner's**
  board. Reading `state.current_node` would let the defender buff the spell
  landing on them.
- It is evaluated **once, at the seed**, and stamped on `CastSpell.seed_damage`
  (copied verbatim by `PropagationConfig.mint`, like `seed_node`). Re-reading per hop
  would compound INT — INT² by hop 2. The formula itself lives in
  `SpellResolver.impact_damage()` — the number the primary target takes;
  `CastSpell.seed_damage` is the same float carried forward for hop
  progressions to fraction themselves against.

`HopDamageProgression` owns the *shape*, and **each class declares
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
amendment in `docs/adr/legacy-mvp-decisions.md`, and the guard test in
`test/unit/spell/test_spell_damage_scaling.gd`.

**`ExpressionProgression`'s seed identifier is `seed_damage`, not `seed`** —
Godot's `Expression` parser reads a bare `seed` as the built-in PRNG function
and fails to parse with "Expected '('". Same collision that named
`CastSpell.seed_node`.

---

## Resolver flow (wave-based)

The resolver processes **waves** (BFS frontiers) so the reducer can merge
simultaneous arrivals before effects fire.

```
seed_wave = [initial CastSpell at seed_node]
while wave not empty:
    # 1. group by target node
    incidents_by_node = group(wave, key=current_node)

    # 2. merge per node, then build this landing's LandingContext
    merged = []
    for node, incidents in incidents_by_node:
        resolved = config.reducer.reduce(incidents, ctx)
        if resolved == null:    # CANCEL — no effect, no propagation from here
            continue
        lctx_of[resolved] = LandingContext.new(cast=ctx, node=node, payload=resolved, incidents=incidents)
        lctx_of[resolved].fill_landing()
        merged.append(resolved)

    # 3. apply effects to merged incidents, bump ctx.global_visit_count
    for state in merged:
        lctx = lctx_of[state]
        for eff in spell.on_hit_effects:
            eff.apply(lctx)
        ctx.global_visit_count[state.current_node] += 1

    # 4. compute next wave: cap visits, filter NARROWS, spread SELECTS,
    #    config MINTS. The visit cap runs FIRST — the filter is set-level, so a
    #    TopTiesFilter must tie-break among reachable candidates, not pick a
    #    winner the cap then deletes. For a pairwise filter the two orders are
    #    identical.
    next_wave = []
    for state in merged:
        lctx = lctx_of[state]
        if state.hops_remaining <= 0: continue
        candidates = [nb for nb in graph.get_neighbours(state.current_node)
                      if ctx.visit_count(nb) < config.max_visits_per_node]
        candidates = config.filter.narrow(candidates, lctx)
        for pick in config.spread.select(candidates, lctx):
            next_wave.append(config.mint(state, pick))
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

- **Filter / Spread / Merger are orthogonal axes.** Mixing-and-matching
  three small subclasses + a handful of scalars gives a combinatorial
  space of spell behaviours. The design-side `spells.md` already
  enumerates a dozen distinct spells expressible this way.
- **Each interface stays RangeFinder-small.** One virtual method, no
  state, easy to read and test in isolation. Composable.
- **Self-loops become a mechanic, not a bug.** A self-loop node
  propagating to itself produces 2 incidents in the next wave; SUM
  reducer collapses them into a doubled hit. That's Resonator's whole
  identity. The current model literally cannot express it.
- **Diamond double-hits are explicit.** They happen iff the spell's reducer is
  SUM and the visit cap allows it (`SumDamageReducer` sums the converging
  damages; `MaxDamageReducer` yields one hit).
- **Configuration replaces subclassing for 95% of spells.** Authors
  ship a new `.tres`, not a new script. The Expression escape hatches
  cover the final 5% without going to a custom subclass.

### Alternatives ruled out

- **Cross-wave merger (buffer all arrivals across the whole cast)** — would let
  a late-arriving incident via a long cycle merge with an earlier one, breaking
  the per-tick feel. The merger is wave-local; late arrivals are additional
  independent hits gated by `max_visits_per_node`.
- **Putting damage scaling on the spread exclusively** — would force every
  spell to use a spread variant just to change falloff. The progression lives on
  `PropagationConfig` (`hop_damage`); the spread does *no* damage math — a spread
  that wants a split hands over a `share` and `PropagationConfig.mint` multiplies.

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
  `HitInstance` — a
  `HitInstance.kind` field (`DAMAGE`/`HEAL`) tells a consumer which.
- **`timeline: Array[PropagationEvent]`** — **additive, spell-only** structure.
  The `SpellResolver` builds it; melee/ranged leave it empty. Each event
  *references* the same `HitInstance` object(s) already in `hits` (shared, not
  copied) via `event.hits`, which is empty (not null)
  for a zero-damage / utility landing that still gets a probe event so it
  animates.
- **`cancellations: Array[SpellCancellation]`** — kept as a replay projection
  *alongside* the new `Verb.CANCEL` events. Additive, not replaced.

The timeline carries the wave structure the resolver already knew at emission
time, so the coordinator never re-derives it by grouping `hits` on `hop_index`.
`hits` stays as the compatibility surface for the ~15 existing readers
(battle_system, both coordinators, tests).


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

The seam widens only when the picture provably cannot re-derive something
(`predecessors`, `visit_index`, `is_terminal`, `incident_shares`, `turn_sign`,
`closed_ring` each exist for exactly one spell that could not otherwise be
drawn), never merely because it would be convenient.


### `incident_shares` — why rank had to cross the seam (#707)

Cyclone splits its damage across turn-ranks, and rank is the whole mechanic: the
sharp turn circulates, the wide turns radiate. The VFX layer cannot recover it.
`CycloneSpread` hands the coefficient over as the pick's `share`, `mint`
multiplies `damage` by it and the coefficient is gone; `CycloneReducer` then
**sums** every incident, and the crit multiplies again at landing. A landed
amount is not invertible.

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

Cyclone's closing hop is the payoff of its design (the crit, plus
`closing_gain` feeding forward as sustain). Lighting the ring *as* a ring needs
the ring, and it lives in
`CastSpell.visited` — a resolver-local the event never carried.

- **The resolver stamps it where the crit is stamped.** `CycloneSpread.closed_ring()`
  truncates `visited` to *exactly* the loop on every close (that truncation is
  what makes every `CycleCondition` crit a real simple cycle of length ≥ 3),
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


### What the coordinator does with it

`MagicBounceCoordinator` walks the timeline grouped by `beat`. Its
`is_empty()` guard reads `timeline`, not `hits`, so a **pure-utility spell
(`power` 0) renders its path** instead of no-op'ing. The fixed wave clock is
untouched:
`wave_started(beat, count)` still fires per beat regardless of lingering visuals
(the load-bearing contract in `.claude/rules/spell-vfx.md`).

The movement verb → `ProjectilePath` mapping and the impact-pinned three-clocks lifetime are in `docs/domain/spell-vfx-kit.md`.


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
3. **Where is it stamped?** At **select, on the pick** (copied onto the child
   by `mint`), if the answer depends on the parent's state. By landing time
   `mint` has already built the child's copy and a reset may have cleared it,
   so the fact is unrecoverable.
   The crit condition then just *reads* the stamped flag — the Design A split
   `ConvergenceCondition` documents, and the reason `CycleCondition` is
   a one-line predicate rather than a re-derivation.

Merge semantics are where emergent behaviour lives, and emergent is not
intended: Cyclone's veto-union once made it a parity detector (counter-rotating
fronts extinguished on even rings) that nothing authored. Cyclone now sums
(see `CycloneReducer`) and gets its identity from a curl instead.


---

## Open questions

1. **Multi-seed targeting.** When RangeFinder eventually returns N
   seeds (AoE / chain-of-N spells), do they share a merger pool (one
   BFS with N starts, merger fires on overlaps) or run as N independent
   casts? Leaning shared, but the call can wait until a multi-seed
   spell actually wants implementing.
2. **CANCEL telemetry.** Whether a fizzle should surface in
   `AttackOutcome` beyond the `cancellations` projection. Out of scope until
   something consumes it.

