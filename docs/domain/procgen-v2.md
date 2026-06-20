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

### Flat values vs ranges (PoE2-style tier rolling)

Tier *and* in-tier variation both live on the pool entry. The entry carries
the `(stat_id, operation, value_range)` triple; on `roll()` it samples the
range and mints a fresh **scalar** `StatModifier`. `StatModifier` itself stays
range-free — procgen is a roll-time concern that never leaks into the runtime
stat pipeline.

```
ModifierPoolEntry
 ├── stat_id: StringName       # &"strength"
 ├── operation: ModifierOp     # ADD_BASE
 ├── value_range: Vector2      # (5.0, 8.0) — tier 2 STR
 ├── cost: int                 # 2 — budget axis
 ├── weight: float              # 6.0 — base sampling weight
 └── tags: Array[StringName]   # [&"str", &"flat", &"tier_2"]

  func roll(rng) -> StatModifier:
	  var m := StatModifier.new()
	  m.stat_id = stat_id
	  m.operation = operation
	  m.value = rng.randf_range(value_range.x, value_range.y)
	  return m
```

This is the **PoE/PoE2 gear-affix model**: each entry IS a tier (cost +
weight + tags), and the range supplies that tier's natural jitter. Three STR
tiers (`+1-4 / +5-8 / +9-13`) replace nine hardcoded integer entries; in-tier
high-rolls give a small "lucky" feel; players just see `+10 STR` and never
need to know which tier rolled it.

Two consequences worth pinning:

- **Crazy-numbers stats fit naturally.** A `tier_5` INT entry can carry
  `value_range = (1000, 10000)` because INT is log10-compressed downstream
  (e.g. `mana_per_turn = floor(log10(INT))`). The pool doesn't know or care
  — it just rolls a scalar. **Invariant:** *if a stat is meant to scale via
  log/sqrt downstream, its pool entries may carry orders-of-magnitude larger
  value ranges than linear stats.* Spell this out wherever crazy-INT ranges
  appear in a balancing doc.
- **CollisionProfile keys on `(stat_id, operation)`.** Range-on-entry doesn't
  change the collision rule: a second draw on the same node still can't
  produce another `(strength, ADD_BASE)` regardless of which tier rolled
  first. The modifier list reads cleanly: `+6 STR | +5% STR | +1 DEX`, never
  `+3 STR | +6 STR`.

---

## Identifiers & validation — keeping `StringName` honest

The whole system leans on `StringName` tags and ids. One typo (`&"str"` vs
`&"strr"`) silently weights nothing. Two layers catch this cleanly without
boxing designers in:

### Layer 1: `procgen/tags.tres` — single source of truth

A small data resource — `Array[StringName]` — listing every legal tag with a
short description per entry. Designers add a tag by editing this file; the
rest of the system reads from it. **Data, not code.** A generated constants
script (`procgen/tags_constants.gd` — `const STR := &"str"` etc.) is optional
sugar for code-side construction; skip it until the lack hurts.

### Layer 2: `@tool` validator on entries + profiles

`ModifierPoolEntry._get_configuration_warnings()` (and the equivalent on
each `WeightProfile`) walks `tags` against the loaded `tags.tres` set and
returns a warning per unknown tag. Designer types a typo into the inspector
→ red banner appears immediately, no need to wait for a test run.

### Layer 3: GUT test as the belt-and-braces backstop

`test/unit/test_procgen_tags.gd` loads every `.tres` under `procgen/`, walks
their `tags` arrays and every `WeightProfile` dictionary, asserts every
member is in `tags.tres`. Catches anything the `@tool` warning missed (a
profile that loaded clean but the entry was edited later, etc.) and gates
pre-push.

`stat_id` typos benefit from the same treatment for free — `StatRegistry`
already enforces the legal set at startup, so a `WeightProfile` that
references an unknown `stat_id` can `push_error` at load time.

**Why not enums / `const` only?** They'd block designers from authoring
entries in the inspector. The data-resource approach lets both audiences
(code authors via constants, designers via inspector) share one source of
truth with one validator.

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

## Worked examples — low, mid, high budget

Three example rolls to anchor the model. Same fixed setup, different budgets.
Numbers are illustrative — the *shape* of the math is the point.

### Shared setup

**Universal pool (excerpt — `value_range` × `cost` × `weight` × `tags`):**

| Entry | value_range | cost | weight | tags |
|---|---|---|---|---|
| STR-T1 | (1, 4) | 1 | 10.0 | str, attack, flat, tier_1, common |
| STR-T2 | (5, 8) | 2 | 6.0 | str, attack, flat, tier_2 |
| STR-T3 | (9, 13) | 3 | 3.0 | str, attack, flat, tier_3 |
| STR%-T2 | (4, 7) | 2 | 4.0 | str, attack, percent, tier_2 |
| STR%-T3 | (9, 12) | 3 | 1.5 | str, attack, percent, tier_3 |
| DEX-T1 | (1, 4) | 1 | 10.0 | dex, attack, flat, tier_1, common |
| DEX-T2 | (5, 8) | 2 | 6.0 | dex, attack, flat, tier_2 |
| INT-T5 | (1000, 10000) | 5 | 0.1 | int, magic, flat, tier_5, rare |
| CON-T1 | (1, 4) | 1 | 10.0 | con, defense, flat, tier_1, common |
| PER-T1 | (1, 4) | 1 | 10.0 | per, sense, flat, tier_1, common |
| SP+/turn | (1, 1) | 3 | 0.4 | sp, growth, tier_3, rare |
| dmg_floor% | (3, 6) | 4 | 0.2 | def, percent, tier_4, rare |
| self-loop | (1, 1) | 6 | 0.05 | structural, tier_5, mythic |

(Similar shape for INT-T1..T3 / WIS / PER tiers — elided.)

**Profile pipeline:** `ArchetypeWeightProfile` → `RadialBandProfile` → `CollisionProfile`.

- **Red (STR) archetype multipliers:** `str ×3.0`, `dex ×0.3`, `int ×0.2`, other ×0.5.
- **Outer-rim band multipliers:** `rare ×4.0`, `mythic ×8.0`, `common ×0.6`.

---

### Low budget = 2 — inner-rim, red cluster, common node

Context: `archetype=red`, `radial_band=inner` (no rare/mythic boost).

**Draw 1 (budget 2)** — affordable subset after archetype weighting:

| Entry | base | × archetype | effective |
|---|---|---|---|
| STR-T1 | 10.0 | ×3.0 | 30.0 |
| STR-T2 | 6.0 | ×3.0 | 18.0 |
| STR%-T2 | 4.0 | ×3.0 | 12.0 |
| DEX-T1, DEX-T2 | 10/6 | ×0.3 | 3.0 / 1.8 |
| INT-T1 (≈10) | 10.0 | ×0.2 | 2.0 |
| CON/WIS/PER T1 | 10.0 ea | ×0.5 | 5.0 ea |

Roll → **STR-T2**. `value_range = (5, 8)` → rng resolves to **+7 STR**.
Budget 0. **Done.**

**Final node modifiers:** `+7 STR`. Predictable STR-cluster flavour from a
small budget.

---

### Mid budget = 4 — mid-rim, red cluster

Context: `archetype=red`, `radial_band=mid` — `rare ×1.5` band bump.

**Draw 1 (budget 4)** — heaviest entry is still STR-T1 (30.0). Roll → **STR-T1** → range (1, 4) → **+3 STR**. Budget 3.

**Draw 2 (budget 3)** — `CollisionProfile` zeroes STR-T1/T2/T3 (same
`(strength, ADD_BASE)`). STR% survives (different op). Affordable subset:

| Entry | effective | notes |
|---|---|---|
| STR%-T2 | 4.0 × 3.0 = 12.0 | |
| STR%-T3 | 1.5 × 3.0 = 4.5 | |
| DEX-T1/T2 | 3.0 / 1.8 | |
| SP+/turn | 0.4 × 0.5 × 1.5 = 0.3 | (other ×0.5, rare ×1.5) |
| STR-T*flat | 0 | collision |

Roll → **STR%-T2** → range (4, 7) → **+5% STR**. Budget 1.

**Draw 3 (budget 1)** — only T1s. STR-T1 collision. Among remaining
attributes' T1s (DEX depressed, others ×0.5), roll → **DEX-T1** → range (1, 4) → **+2 DEX**. Budget 0.

**Final node modifiers:** `+3 STR | +5% STR | +2 DEX`. The "STR specialist
with a splash" pattern.

---

### High budget = 7 — outer-rim, red cluster

Context: `archetype=red`, `radial_band=outer` — `rare ×4.0`, `mythic ×8.0`,
`common ×0.6`. This is where **rare odds compound across multiple draws**.

**Draw 1 (budget 7)** — fully open. Notable effective weights:

| Entry | base | × arch | × band | effective | Pr |
|---|---|---|---|---|---|
| STR-T1 (common) | 10.0 | ×3.0 | ×0.6 | 18.0 | ~60 % |
| STR-T2 | 6.0 | ×3.0 | — | 18.0 | (T2 not tagged common) |
| STR-T3 | 3.0 | ×3.0 | — | 9.0 | |
| INT-T5 (rare) | 0.1 | ×0.2 | ×4.0 | 0.08 | ~0.3 % |
| SP+/turn (rare) | 0.4 | ×0.5 | ×4.0 | 0.8 | ~2.7 % |
| dmg_floor% (rare) | 0.2 | ×0.5 | ×4.0 | 0.4 | ~1.3 % |
| self-loop (mythic) | 0.05 | ×0.5 | ×8.0 | 0.2 | ~0.7 % |

**Pr(any rare-or-mythic this draw) ≈ 5 %.** Roll → **STR-T3** → range (9, 13) → **+11 STR**. Budget 4.

**Draw 2 (budget 4)** — STR-T* flat collision-blocked. Now:

| Entry | effective | notes |
|---|---|---|
| STR%-T2 | 12.0 | |
| STR%-T3 | 4.5 | |
| DEX-T2 | 1.8 | |
| dmg_floor% (rare, cost 4) | 0.4 × 1 = 0.4 | newly affordable, still ~1 % |
| SP+/turn (rare, cost 3) | 0.8 | |
| INT-T5 (rare, cost 5) | unaffordable | |
| self-loop (mythic, cost 6) | unaffordable | |

Roll → **STR%-T2** → range (4, 7) → **+6% STR**. Budget 2.

**Draw 3 (budget 2)** — STR flat + percent both collision-blocked. Roll →
**CON-T2** (5.0 effective) → range (5, 8) → **+5 CON**. Budget 0.

**Final node modifiers:** `+11 STR | +6% STR | +5 CON`. A solid red-cluster
outer-rim node — strong STR identity, a defensive splash.

#### What if we'd hit a rare?

**Pr(at least one rare across all 3 draws) ≈ 1 − (1 − 0.05)³ ≈ 14 %.** Roughly
1 in 7 high-budget outer-rim nodes carries something interesting. **Levers
to crank that up:**

1. **Raise the outer-rim `rare ×` multiplier** — most direct.
2. **Add a `MinPerRegion` `GuaranteedPlacement`** ("≥1 rare somewhere in the
   outer rim"). Turns probabilistic into guaranteed-but-RNG-located. Strong
   tool for "every run has *something*."
3. **Local archetype-rare affinity** — red+outer specifically boosts
   `str`-tagged rares. Locality of flavour.
4. **Budget scaling via `BudgetPolicy.budget_field`** — outer rim gets
   higher budgets → more draws → multiplicatively more chances.

All four are existing `WeightProfile` / `GuaranteedPlacement` / `BudgetPolicy`
knobs. No new engine code, all `.tres`.

---

## Migration sketch (very rough)

1. Reshape `ModifierPoolEntry`: add `stat_id`, `operation`, `value_range`,
   `tags`; remove the embedded `StatModifier` resource (the entry now mints
   one on `roll()`). Migrate existing presets.
2. Land `procgen/tags.tres` + `@tool` validator + GUT test (the typo backstop)
   in the same change as step 1 so new tags are gated from day one.
3. Extract `WeightContext`, `WeightProfile` (abstract), and
   `ArchetypeWeightProfile` + `CollisionProfile` (the two minimum-viable
   profiles).
4. Replace `NodeTypeDef.modifier_pool` per-type pools with a single
   `GraphProcgenConfig.modifier_pool` + an archetype-keyed weight profile.
5. Add `BudgetPolicy` (extract from `NodeTypeDef`, keep type-bound override).
6. Add `AddonPolicy` + `AddonPool` + first concrete addon entries.
7. `GuaranteedPlacement` pass — start with `MinNearStartingPoints` only.
8. `ArchetypeBalancer` — opt-in, off by default until tuned.

Each step is shippable and reversible. The existing v1 procgen keeps working
in the meantime — `GraphProcgenConfig` grows new optional fields, doesn't
break old presets.
