# Procgen v2 — content composition

> Sketch / design doc. Implementation TBD. Companion to [procgen.md](procgen.md)
> (which covers the existing geometry/topology pipeline — Poisson, Delaunay,
> clustering). v2 is about **what fills the nodes**, not where they sit.
>
> Status: design draft. Numbers and resource names are placeholders.

## Goal in one paragraph

We want one universal **modifier pool** that every node could in principle draw
from, but with **per-context weighting** so a "red/STR" cluster actually feels
like a STR cluster — without ever fully zeroing other stats (rare cross-rolls
are the spice). Plus a second pass for **addons** with its own budget,
**guaranteed placements** so essential content (xp/turn, etc.) is never absent,
and a **running-distribution rebalance** so RNG streaks don't tilt the level.

All of this must be configurable as composable `.tres` resources — same
philosophy as the existing `GraphProcgenConfig` / `NodeTypeDef` / `ModifierPool`
trio. Designers tune by swapping subresources, not by editing code.

---

## The mental model

```
┌─────────────────────────────────────────────────────────────────┐
│  GraphProcgenConfig (the level recipe)                          │
│  ├── topology knobs ............ (unchanged from v1)            │
│  ├── ModifierPool (universal) .. one shared pool of options     │
│  ├── Array[WeightProfile] ...... pipeline of weight modulators  │
│  ├── BudgetPolicy .............. how big each node's roll is    │
│  ├── AddonPolicy ............... second pass for addons         │
│  ├── Array[GuaranteedPlacement]. essential content invariants   │
│  └── ArchetypeBalancer ......... running-count rebalance        │
└─────────────────────────────────────────────────────────────────┘
```

Generation order:
1. **Topology** (Poisson + Delaunay + MST — v1, unchanged).
2. **Archetype assignment** (cluster Voronoi — v1, but its weights run through
   `ArchetypeBalancer`).
3. **Guaranteed placements** — pre-pass that reserves slots/decorates nodes for
   essential content (e.g. one `xp_per_turn` node within N hops of every
   starting node).
4. **Per-node modifier pass** — roll budget → repeatedly draw from the
   universal pool with weights resolved by the `WeightProfile` pipeline →
   subtract cost → repeat.
5. **Per-node addon pass** — separate budget, separate pool, but `WeightProfile`
   may correlate with the modifiers already rolled.

---

## The universal pool + WeightProfile pipeline

The user's intuition: *weighting is a function of archetype.* Mostly yes — but
archetype is one input among several. Modeling it as a **pipeline of
WeightProfiles** keeps each input separable and lets designers compose them.

### Inputs a `WeightProfile` can read

Each profile declares which fields of a small `WeightContext` struct it cares
about. The pipeline assembles the context once per node, then each profile
returns a `Dictionary[StringName, float]` of multipliers keyed by pool entry id.

| Input | Source | Example use |
|---|---|---|
| `archetype` | type assignment from cluster pass | STR cluster boosts STR-tagged entries ×3.0, depresses INT to ×0.2 (never 0) |
| `position` | world position | outer rim boosts rare-tier entries |
| `radial_band` | distance bucket from center | inner = base modifiers, mid = INCREASE, outer = MULTIPLY |
| `theme` | level theme (Classic Tree / Web / Spiral / …) | Web boosts INT-flavoured entries everywhere |
| `degree` | post-edge-pruning degree | high-degree nodes bias toward spell-related modifiers |
| `neighborhood_archetypes` | counts of types within k hops | "anti-clumping" — if 4/4 neighbors are STR, depress STR weight here |
| `already_rolled` | modifiers already picked on *this* node | enforces "no same (stat, op) twice" (weight → 0 for collisions); also lets you bias the *next* draw |
| `node_index` / `rng` | for deterministic noise | jitter ±10 % so two identical-context nodes still differ slightly |
| `run_state` | level number, difficulty | later levels boost rarer pool entries |

`WeightContext` is just a `Resource` (or a plain RefCounted bag) — all fields
optional. Profiles ignore what they don't need.

### Profile types (each its own Resource subclass)

```
WeightProfile (abstract)
 ├── ArchetypeWeightProfile   # tag-based: pool entries declare tags, profile
 │                             # has a Dictionary[archetype → Dictionary[tag → mult]]
 ├── RadialBandProfile        # position-based band multipliers
 ├── ThemeProfile             # flat per-archetype-or-tag multipliers tied to a theme
 ├── NeighborhoodProfile      # anti-clumping (or pro-clumping) by k-hop neighborhood
 ├── CollisionProfile         # enforces "no same (stat, op) twice within a node"
 ├── DegreeProfile            # bias by post-prune degree
 └── ExpressionWeightProfile  # escape hatch: GDScript Expression-based, like ExpressionFormula
```

All composable. The pipeline runs them in order, multiplying multipliers into
a working weight per pool entry, then samples. **Floors apply at the end**: any
pool entry whose final weight is ≤ `min_weight` is either clamped to
`min_weight` (default `0.05` of original) or dropped — configurable per profile.

This is the same shape as the stat modifier pipeline (`StatBoard`'s
`ModifierBins.compute()`), which is good — same mental model, same debugging
tools could apply (a "why does this node have a 7 % chance of rolling INT?"
trace dump is a one-day feature).

### Pool entry tags

Pool entries grow a `tags: Array[StringName]` field (e.g. `[&"str", &"attack",
&"flat", &"common"]`). Profiles work on tags, never on hardcoded entry ids. The
existing `ModifierPoolEntry.cost` stays — it's the budget axis, orthogonal to
weight.

This gives you the "tiered modifiers" you asked about for free: entries tagged
`[&"str", &"tier_1"]` cost 1, `[&"str", &"tier_2"]` cost 2, etc., and a
`CollisionProfile` that zeroes weight for any entry with overlapping
`(stat_id, operation)` already on the node neatly forbids second-draw
duplication. **No fusion.** A re-roll picks a different (stat, op) pair —
budget accounting stays honest, modifier lists read cleanly (no "+1 STR | +1
STR" awkwardness).

If you'd later want "+1–3 STR" random-range entries instead of discrete tiers,
that lives entirely inside the *entry* (a `RangeModifier` resource that resolves
at roll time), not in the weighting pipeline.

---

## BudgetPolicy

Currently each `NodeTypeDef` carries `budget_min`/`budget_max`. v2 promotes
this into a `BudgetPolicy` subresource so it can be modulated independently of
type:

```
BudgetPolicy
 ├── base_min / base_max
 ├── archetype_multiplier  # optional Dictionary[archetype → float]
 ├── budget_field          # ScalarField (already exists as budget_field)
 └── role_bonus            # extra budget for special roles (boss-adjacent, etc.)
```

`budget_field` (the existing radial gradient hook) migrates into here cleanly.

---

## AddonPolicy — separate budget, correlated weights

```
AddonPolicy
 ├── chance_per_node           # base probability a node gets ANY addon
 ├── addon_budget              # separate from modifier budget
 ├── AddonPool                 # parallel to ModifierPool — Array[AddonPoolEntry]
 └── Array[WeightProfile]      # may read `already_rolled` from the modifier pass!
```

The interesting hook: an addon's weight profile pipeline reads the same
`WeightContext` but with `already_rolled` populated from the modifier pass. So
"a Reinforcement addon is more likely on a node that already rolled CON-flavor
modifiers" is one line in a profile, not a special case. Same for "Spikes more
likely on a STR-tagged node."

**Separate budget**, not shared, because:
- Tuning one without affecting the other is straightforward.
- Designers think about "how many modifier slots does this archetype get?" and
  "how often does this archetype get an addon?" as independent dials.
- A shared budget creates "is this addon worth N modifier draws?" math at
  every step — annoying and brittle.

---

## GuaranteedPlacement — essential content invariants

Pre-pass. Each `GuaranteedPlacement` is a constraint the procgen must satisfy
before the random fill runs.

```
GuaranteedPlacement (abstract)
 ├── MinNearStartingPoints   # ≥N nodes matching a tag within K hops of every starter
 ├── MinPerArchetype         # global floor per archetype
 ├── ExactCount              # exactly N of something across the map
 └── Keystones               # specific named nodes placed at chosen positions
```

The classic "natural expansion" case is `MinNearStartingPoints(tag=&"xp_per_turn", count=1, max_hops=3)`. The pass runs before the modifier roll, decorates the
chosen nodes with a "pre-filled" marker (so the regular pass skips them or
treats them as partial-budget), and emits a warning if the constraint can't be
satisfied (impossible map shape, etc.).

This is also where keystones / fixed-content special nodes plug in. They're
just `GuaranteedPlacement` variants that target specific positions or
topological roles (e.g. "place a keystone on the highest-degree node within X
of the rim").

---

## ArchetypeBalancer — running-distribution rebalance

The Pittman-style dynamic-Markov idea. Instead of `NodeTypeDef.weight` being
the *final* weight for every cluster-seed pick, run it through:

```
effective_weight(t) = base_weight(t)
					× (target_ratio(t) − current_ratio(t) + ε)
```

where `current_ratio(t)` is the running fraction of seeds already assigned to
type `t`, `target_ratio(t)` is the designer's intended share, and `ε` keeps the
multiplier strictly positive (no archetype gets locked out). `ε` is the lever:
small ε = strict ratios, large ε = looser/noisier.

This applies per *cluster seed pick* (not per node, since nodes inherit their
seed's archetype with a small `cluster_jitter` chance). So with 6 cluster seeds
and a target 1:1:1 across 3 archetypes you get a strong bias toward 2:2:2 even
if the RNG would naturally land 4:1:1.

Configurable as:

```
ArchetypeBalancer
 ├── target_ratios     # Dictionary[StringName, float] — relative shares
 ├── strength_epsilon  # ε — 0.01 = strict, 0.5 = light bias
 └── enabled           # bool — fall back to plain weighted-random if off
```

---

## Open questions for the design pass

- **Does `already_rolled` weight the *next draw* within the same node, or only
  hard-forbid collisions?** Forbid-only is simpler; soft-bias is more
  expressive (e.g. "if you just rolled STR-flat, slightly favor STR-percent
  next"). Lean: forbid-only for v2.0, leave the hook for soft-bias.
- **Should `WeightProfile` be allowed to make weights conditional on `cost`?**
  E.g. "in outer rim, double the weight of cost-3 entries." Cheap to add later.
- **Where do per-node *intrinsic* modifiers live?** (Modifiers a node keeps for
  itself, like local `node_health`.) Probably a third small pass after addons,
  with its own (tiny) pool. Or embedded as a tag on regular pool entries that
  routes them to `local_modifiers` instead of `modifiers`.
- **Theme integration.** Themes (Web, Spiral, …) likely emit *both* a topology
  preset and a `WeightProfile` — the former changes geometry, the latter
  changes flavour. Worth a `ThemeProfile.tres` per theme that bundles them.
- **Debug visibility.** Once the pipeline exists, a "explain this node's
  rolls" debug overlay (right-click a generated node → see the weight table
  that picked each modifier) would be load-bearing for balancing. Plan for it,
  don't build it day-one.

---

## Migration sketch (very rough)

1. Extract `WeightContext`, `WeightProfile` (abstract), and `ArchetypeWeightProfile`
   + `CollisionProfile` (the two minimum-viable profiles).
2. Add `tags: Array[StringName]` to `ModifierPoolEntry`.
3. Replace `NodeTypeDef.modifier_pool` per-type pools with a single
   `GraphProcgenConfig.modifier_pool` + an archetype-keyed weight profile.
4. Add `BudgetPolicy` (extract from `NodeTypeDef`, keep type-bound override).
5. Add `AddonPolicy` + `AddonPool` + first concrete addon entries.
6. `GuaranteedPlacement` pass — start with `MinNearStartingPoints` only.
7. `ArchetypeBalancer` — opt-in, off by default until tuned.

Each step is shippable and reversible. The existing v1 procgen keeps working
in the meantime — `GraphProcgenConfig` grows new optional fields, doesn't
break old presets.
