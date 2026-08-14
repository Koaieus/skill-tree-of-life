@tool
class_name GraphProcgenConfig
extends Resource

## Bundle of knobs feeding [GraphProcgen]. Save as `.tres` under
## `procgen/presets/` to make a preset; the sandbox + future level pickers
## just take one of these and run.

## RNG seed. 0 = randomise per run.
@export var seed: int = 0

# ── Topology ──────────────────────────────────────────────────────────────

## Target node count. Poisson sampling stops when the active list empties,
## so the actual count is bounded by what the shape + spacing allow.
@export_range(50, 3000, 10) var node_count: int = 300
## Visual + collision radius pushed onto every generated SkillNode.
@export_range(1., 64., 1.) var node_radius: float = 32.0
## Extra clearance between nodes beyond `2 × node_radius`. Higher = airier.
@export_range(1., 128., 1.,) var node_padding: float = 14.0
## Fraction of Delaunay edges to keep beyond the minimum spanning tree.
## 0 = MST only (every node connected, sparsest planar). 1 = full Delaunay
## (densest planar). Spans shortest-edges-first so the result stays organic.
@export_range(0.0, 1.0) var connectivity: float = 0.55

## 4-tier floor-guaranteed staged self-loop draw (#42). Tier 1 draws
## `floor(N × p1)` nodes uniformly from all generated nodes (without
## replacement); tier k draws `floor(K_{k-1} × p_k)` from the previous tier's
## set. Each tier then does ONE Bernoulli on the fractional remainder to add
## +1 (floor + 0-or-1), and a node that hits tier k gets exactly k self-loops.
## Cores are NOT excluded from the tier-1 pool. The number of tier knobs IS
## the cap (4) — raising it later means adding a tier-5 knob.
@export_range(0.0, 1.0) var self_loop_tier1_rate: float = 0.10
## Fraction of the tier-1 set upgraded to exactly 2 self-loops.
@export_range(0.0, 1.0) var self_loop_tier2_rate: float = 0.17
## Fraction of the tier-2 set upgraded to exactly 3 self-loops.
@export_range(0.0, 1.0) var self_loop_tier3_rate: float = 0.30
## Fraction of the tier-3 set upgraded to exactly 4 self-loops (the cap).
@export_range(0.0, 1.0) var self_loop_tier4_rate: float = 0.30


# ── Shape ─────────────────────────────────────────────────────────────────

@export var shape_mask: ShapeMask

# ── Starting points ───────────────────────────────────────────────────────

## Anchor points that MUST become skill nodes. Seeded into the Poisson
## sampler before random points, so they're guaranteed to land and the rest
## of the graph respects their spacing. Default = single core at (0,0).
## After generation, [GraphProcgen.generate] returns the SkillNodes that
## landed on these (in order) so the caller can wire them as cores.
@export var starting_points: Array[StartingPoint] = []

## Extra anchors placed randomly inside [member shape_mask] before Poisson
## body sampling — typically the NPC opponents on a level. Each random anchor
## is rejection-sampled to keep `> viability_radius` away from every prior
## anchor (manual + already-placed random). 0 = none.
@export var n_random_starters: int = 0
## Min distance from any other starter (manual or random) that a random
## anchor must respect. "Viability" because the same separation gates several
## gameplay concerns at once — territory growth space, sensible AI separation,
## avoiding immediate-conflict starts. Default 0 = no minimum (caller opted in
## by setting n_random_starters > 0 but didn't specify spacing).
@export var viability_radius: float = 0.0
## Generated `StartingPoint.id`s use this prefix plus an index — e.g.
## "enemy_0", "enemy_1". Inert if [member n_random_starters] is 0.
@export var random_starter_id_prefix: StringName = &"enemy"
## Bounded retry per random anchor. Hit it without placing → warn and skip.
@export var random_starter_max_tries: int = 200

# ── Content: archetypes + modifiers ───────────────────────────────────────

## Phased-draw modifier content. The per-node v4 draw spends the rolled
## budget until broke across pools whose `archetype_stat` matches the node's
## primary_stat (or is universal `&""`), then aggregates per (stat, op).
## Unset = nodes roll no modifiers. See docs/domain/procgen-v4.md.
@export var modifier_pool_set: ModifierPoolSet
## Typed as Array[Resource] because Godot's TypedArray check rejects
## subclasses of an abstract base — concrete profiles (Archetype/Collision/Radial)
## couldn't coexist in `Array[WeightProfile]`. Runtime dispatches via
## [method WeightProfile.multiplier_for] duck-typing.
@export var weight_profiles: Array[Resource] = []

## Per-node budget knobs — the base range plus archetype / role / positional
## multipliers that decide each node's modifier budget. Unset = budget 0
## (nodes roll no modifiers). See [BudgetPolicy].
@export var budget_policy: BudgetPolicy

## Archetype policies. When non-empty, the cluster pass runs cluster-planned
## BFS-grow using these per-archetype target ratios + size distributions;
## empty leaves every node archetype-less (and content-less).
@export var archetypes: Array[ArchetypePolicy] = []

## Second-pass addon roll. Unset = no addons attached by procgen.
@export var addon_policy: AddonPolicy

## Third-pass spell-grant distribution (#206). Unset (or [member spell_grant_ratio]
## 0) = no grants attached by procgen. Gated to INT-archetype nodes only —
## see [GraphProcgenSpellGrants]. `ratio` is the level's grant budget as a
## fraction of the INT-node count (1.0 = one grant per INT node on average),
## split across the pool's entries by weight and Poisson-rolled per entry —
## every entry in the pool is guaranteed at least one copy on the level.
@export var spell_grant_pool: SpellGrantPool
@export_range(0.0, 1.0) var spell_grant_ratio: float = 0.0

## Pre-roll constraints. Each runs against a [PlacementContext] and may stamp
## role tags (consumed by [BudgetPolicy.role_bonus]) or reserve nodes for
## special content. See docs/domain/procgen-v2.md "GuaranteedPlacement".
## Typed Array[Resource] for the same reason weight_profiles is — concrete
## placement subclasses can't coexist in a typed abstract-base array.
@export var guaranteed_placements: Array[Resource] = []

## Optional running-count rebalance for jitter rerolls + fallback assignment.
## See [ArchetypeBalancer]. Off by default; set + flip `enabled` to dampen RNG
## streaks against the target ratios.
@export var archetype_balancer: ArchetypeBalancer

## Post-clustering territory stamps. After BFS-grow archetype assignment
## ([member archetypes]), each stamp overrides the archetype of nodes inside
## its region — a euclidean disc or a topological BFS flood. Stamps run
## before the content-roll loop, so overridden nodes get the new archetype's
## colour, primary-stat bias, and budget multipliers. See [ArchetypeStamp].
@export var archetype_stamps: Array[ArchetypeStamp] = []
