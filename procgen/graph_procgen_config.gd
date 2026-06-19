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
@export var node_count: int = 300
## Visual + collision radius pushed onto every generated SkillNode.
@export var node_radius: float = 32.0
## Extra clearance between nodes beyond `2 × node_radius`. Higher = airier.
@export var node_padding: float = 14.0
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
