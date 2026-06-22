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

# ── Base types + modifiers ────────────────────────────────────────────────

@export var node_types: Array[NodeTypeDef] = []
## Number of cluster seeds. Each seed picks a type weighted by
## [member NodeTypeDef.weight]; each generated node inherits its nearest
## seed's type. Higher = smaller, more fragmented clusters.
@export var cluster_count: int = 6
## 0 = pure Voronoi (hard cluster borders). 1 = ignore clustering, each
## node rolls a type independently. Mix in between for soft edges.
@export_range(0.0, 1.0) var cluster_jitter: float = 0.15

# ── Spatial modulation ────────────────────────────────────────────────────

## Multiplies each node's rolled modifier budget by `field.sample(position)`.
## 1.0 anywhere = no modulation (matches the unset / ConstantField default).
## Pair a [RadialGradientField] with a circular shape for the classic
## "weak center, strong rim" gradient. Unset = neutral.
@export var budget_field: ScalarField

# ── v2 universal pool (optional) ──────────────────────────────────────────

## Procgen v2 (see docs/domain/procgen-v2.md). When set, the per-node modifier
## pass draws from this universal pool instead of the per-[NodeTypeDef] pools.
## `weight_profiles` provide per-entry sampling biases (archetype-affinity,
## collision-block, radial-band, etc.) composed multiplicatively. Leave unset
## to keep v1 behaviour — the per-type pools on `node_types` are used.
@export var modifier_pool: ModifierPool
## v3 phased-draw modifier content. When set, takes priority over
## `modifier_pool`: the draw loop runs as primary → off-attribute (cost-capped)
## → universal → rare, reading `archetype_stat` / `role` off each [TierPool]
## to slice the set per phase. Unset = falls back to `modifier_pool`.
@export var modifier_pool_set: ModifierPoolSet
## Typed as Array[Resource] because Godot's TypedArray check rejects
## subclasses of an abstract base — concrete profiles (Archetype/Collision/Radial)
## couldn't coexist in `Array[WeightProfile]`. Runtime dispatches via
## [method WeightProfile.multiplier_for] duck-typing.
@export var weight_profiles: Array[Resource] = []

## Per-node budget knobs. When non-null, overrides the v1
## [NodeTypeDef.budget_min] / `budget_max` + `budget_field` combo and uses its
## own archetype/role/field multipliers instead. Unset = v1 fallback.
@export var budget_policy: BudgetPolicy

## v2 archetype policies. When [member use_archetype_policies] is true (and
## this array is non-empty), the cluster pass switches from v1 Voronoi-on-
## NodeTypeDef to v2 cluster-planned BFS-grow using these per-archetype
## target ratios + size distributions.
@export var archetypes: Array[ArchetypePolicy] = []
@export var use_archetype_policies: bool = false

## Second-pass addon roll. Unset = no addons attached by procgen.
@export var addon_policy: AddonPolicy

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
